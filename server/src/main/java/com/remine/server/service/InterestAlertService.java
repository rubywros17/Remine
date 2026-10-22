package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestAlert;
import com.remine.server.domain.interest.InterestAlertRepository;
import com.remine.server.domain.tag.TagRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.HashSet;
import java.util.Set;

/**
 * 주 1회, 기기마다 관심사 1순위를 알림 후보(PENDING)로 저장한다. 발송은 다음 단계.
 *
 * <ul>
 *   <li>멱등: 기기당 한 주에 하나(device + week_start unique). 같은 주에 다시 돌면 이미 있는 기기는 건너뛴다.</li>
 *   <li>쿨다운: 최근 alertCooldownDays 안에 후보가 됐던 태그는 다시 고르지 않고 다음 순위를 본다.
 *       횟수가 늘어도 예외는 두지 않는다(주 1건이라 같은 태그 반복보다 다른 관심사에 자리를 준다).</li>
 *   <li>기기마다 따로 저장해 한 기기의 실패가 다른 기기를 되돌리지 않는다.</li>
 * </ul>
 * 로그에는 건수만 남긴다(태그 이름 없음).
 */
@Service
@RequiredArgsConstructor
public class InterestAlertService {

    private static final Logger log = LoggerFactory.getLogger(InterestAlertService.class);

    private final DeviceRepository deviceRepository;
    private final TagRepository tagRepository;
    private final InterestAlertRepository alertRepository;
    private final InterestService interestService;
    private final RemineProperties properties;
    private final Clock clock;

    // ponytail: 전 기기를 한 번에 순회한다. 기기 수가 늘면 페이지 단위 처리·여러 인스턴스면 분산 락(ShedLock 등).
    @Scheduled(cron = "${remine.interest.alert-cron}", zone = "Asia/Seoul")
    public void createWeeklyAlerts() {
        LocalDateTime now = LocalDateTime.now(clock);
        LocalDate weekStart = now.toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate cooldownAfter = weekStart.minusDays(properties.interest().alertCooldownDays());

        int devices = 0;
        int created = 0;
        for (Long deviceId : deviceRepository.findAllIds()) {
            devices++;
            if (createFor(deviceId, now, weekStart, cooldownAfter)) {
                created++;
            }
        }
        log.info("interest alerts weekStart={} devices={} created={}", weekStart, devices, created);
    }

    private boolean createFor(Long deviceId, LocalDateTime now, LocalDate weekStart, LocalDate cooldownAfter) {
        if (alertRepository.existsByDeviceIdAndWeekStart(deviceId, weekStart)) {
            return false;
        }
        Set<Long> cooling = new HashSet<>(alertRepository.findTagIdsSince(deviceId, cooldownAfter));
        return interestService.detect(deviceId, now).stream()
                .filter(interest -> !cooling.contains(interest.tagId()))
                .findFirst()
                .map(top -> {
                    try {
                        alertRepository.save(new InterestAlert(deviceRepository.getReferenceById(deviceId),
                                tagRepository.getReferenceById(top.tagId()), top.captureCount(), weekStart));
                        return true;
                    } catch (DataIntegrityViolationException e) {
                        return false; // 동시에 돈 다른 실행이 먼저 저장했다(같은 주 1건 보장)
                    }
                })
                .orElse(false);
    }
}
