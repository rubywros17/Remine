package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestAlert;
import com.remine.server.domain.interest.InterestAlertRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.exception.NoFcmTokenException;
import com.remine.server.exception.PushDisabledException;
import com.remine.server.push.PushMessage;
import com.remine.server.push.PushSender;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Map;

/**
 * 이번 주 PENDING 관심사 알림을 보낸다. 집계(주 1회)와 따로 돌아 그 주 안에서 실패를 다시 보낸다.
 *
 * <ul>
 *   <li>시작할 때 지난주 이전 PENDING은 EXPIRED로 정리한다(지나간 관심사는 보내지 않는다).</li>
 *   <li>SENT → 다시 보내지 않음 / FAILED → PENDING 그대로, 다음 실행에 재시도 /
 *       INVALID_TOKEN → 기기 토큰만 지움(앱이 새 토큰을 올리면 그 주 안에 다시 간다).</li>
 *   <li>FCM 호출은 트랜잭션 밖에서, 결과 반영은 건마다 따로 저장한다(한 건 실패가 다른 건을 되돌리지 않게).</li>
 * </ul>
 * 알림에는 태그·횟수·카테고리만 담는다(OCR 원문·요약 없음). 로그는 건수만.
 */
@Service
public class InterestPushService {

    private static final Logger log = LoggerFactory.getLogger(InterestPushService.class);
    /** 테스트 알림에서 관심사가 아직 없을 때 쓰는 예시. */
    static final String EXAMPLE_TAG = "신발";

    private final InterestAlertRepository alertRepository;
    private final DeviceRepository deviceRepository;
    private final InterestService interestService;
    private final PushSender sender; // null이면 푸시 꺼짐(키 파일 없음)
    private final TransactionTemplate tx;
    private final Clock clock;

    public InterestPushService(InterestAlertRepository alertRepository, DeviceRepository deviceRepository,
                               InterestService interestService, ObjectProvider<PushSender> sender,
                               PlatformTransactionManager transactionManager, Clock clock) {
        this.alertRepository = alertRepository;
        this.deviceRepository = deviceRepository;
        this.interestService = interestService;
        this.sender = sender.getIfAvailable();
        this.tx = new TransactionTemplate(transactionManager);
        this.clock = clock;
        if (this.sender == null) {
            log.warn("푸시 꺼짐: remine.fcm.credentials-file이 비었거나 파일이 없습니다. 관심사 알림은 보내지 않습니다.");
        }
    }

    // ponytail: 이번 주 PENDING을 한 번에 읽어 순차 발송한다. 기기가 많아지면 페이지 단위 + FCM sendEach(500개 묶음).
    @Scheduled(cron = "${remine.push.send-cron}", zone = "Asia/Seoul")
    public void sendPending() {
        if (sender == null) {
            return;
        }
        LocalDateTime now = LocalDateTime.now(clock);
        LocalDate weekStart = now.toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        Integer expired = tx.execute(status -> alertRepository.expireBefore(weekStart));

        List<InterestAlert> pending = alertRepository.findPendingToSend(weekStart);
        int sent = 0;
        int invalid = 0;
        for (InterestAlert alert : pending) {
            String token = alert.getDevice().getFcmToken();
            switch (sender.send(token, messageFor(alert))) {
                case SENT -> {
                    tx.executeWithoutResult(status ->
                            alertRepository.findById(alert.getId()).ifPresent(a -> a.markSent(now)));
                    sent++;
                }
                case INVALID_TOKEN -> {
                    tx.executeWithoutResult(status -> deviceRepository.findById(alert.getDevice().getId())
                            .ifPresent(d -> d.clearFcmToken(token)));
                    invalid++;
                }
                case FAILED -> {
                    // PENDING 그대로 → 다음 실행에 재시도
                }
            }
        }
        log.info("interest push weekStart={} pending={} sent={} invalidToken={} expired={}",
                weekStart, pending.size(), sent, invalid, expired);
    }

    /**
     * 개발용 테스트 알림(DevPushController). 이 기기의 지금 1순위 관심사로, 없으면 예시 관심사로 1건 보낸다.
     * interest_alert는 읽지도 쓰지도 않는다(주간 발송·쿨다운에 영향 없음). 무효 토큰이어도 토큰을 지우지 않는다.
     */
    public PushSender.Result sendTest(Long deviceId) {
        Device device = deviceRepository.findById(deviceId).orElseThrow(() -> new DeviceNotFoundException(deviceId));
        if (device.getFcmToken() == null) {
            throw new NoFcmTokenException();
        }
        if (sender == null) {
            throw new PushDisabledException();
        }
        PushMessage message = interestService.detect(deviceId, LocalDateTime.now(clock)).stream()
                .findFirst()
                .map(top -> message(top.tag(), top.captureCount(), top.category()))
                .orElseGet(() -> message(EXAMPLE_TAG, 3, Category.SHOPPING));
        return sender.send(device.getFcmToken(), message);
    }

    static PushMessage messageFor(InterestAlert alert) {
        return message(alert.getTag().getName(), alert.getCaptureCount(), alert.getCategory());
    }

    /** 문구는 해요체, 내용은 태그·횟수뿐. data는 앱이 열 화면(카테고리 + 태그 필터). */
    static PushMessage message(String tag, int count, Category category) {
        return new PushMessage(
                "Remine",
                "요즘 '%s'%s %d번 캡처했어요. 다시 볼까요?".formatted(tag, objectParticle(tag), count),
                Map.of("type", "interest", "tag", tag, "category", category.name()));
    }

    /** 받침이 있으면 '을', 없으면 '를'("신발을", "드라마를"). 한글로 끝나지 않으면 "을(를)". */
    static String objectParticle(String word) {
        char last = word.isEmpty() ? ' ' : word.charAt(word.length() - 1);
        if (last < '가' || last > '힣') {
            return "을(를)";
        }
        return (last - '가') % 28 == 0 ? "를" : "을";
    }
}
