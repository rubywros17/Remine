package com.remine.server.service;

import com.remine.server.ServerApplication;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.usage.DailyUsageRepository;
import com.remine.server.domain.usage.DailyUsageRepository.LlmCalls;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;

/**
 * 예전 스크린샷(기기 등록 전에 찍힌 캡처) 하루 한도. 두 가지를 함께 센다.
 * <ul>
 *   <li>기기당 하루 장수(remine.analyze.daily-older-limit) — <b>한국 시간</b> 날짜</li>
 *   <li>서버 전체 하루 LLM 호출 예산 중 예전 몫(daily-llm-call-budget × older-call-share-percent) —
 *       Gemini 무료 한도가 초기화되는 <b>태평양 시간</b> 날짜(서머타임은 ZoneId가 반영)</li>
 * </ul>
 * 분석 전에 {@link #reserve}로 예약하고, 분석 뒤 {@link #settle}로 실패한 장·쓰지 않은 호출을 돌려준다.
 * 예약 때의 두 날짜를 그대로 쓰므로 자정을 넘겨 정산해도 예약한 날에서 돌려준다.
 * 새 스크린샷은 막지 않고 호출 수만 {@link #recordNewCalls}로 남긴다.
 *
 * <p>잠금 순서는 항상 기기 행 → 서버 행이라 동시 요청끼리 교착하지 않는다. 서버 행은 예약 순간에만 잠깐 잡는다(LLM 호출 중에는 안 잡음).
 */
@Service
@RequiredArgsConstructor
public class OlderQuota {

    static final ZoneId DEVICE_ZONE = ZoneId.of(ServerApplication.ZONE);
    static final ZoneId LLM_ZONE = ZoneId.of("America/Los_Angeles");

    private final DailyUsageRepository repository;
    private final RemineProperties properties;
    private final Clock clock;

    /** 예약 결과: 앞에서부터 items장을 분석해도 된다. calls는 그 장들에 잡아 둔 예상 호출 수. */
    public record Reservation(LocalDate deviceDate, LocalDate llmDate, int items, int calls) {
    }

    /**
     * 예전 스크린샷을 앞에서부터 가능한 만큼 예약한다(남은 몫보다 많으면 뒤쪽이 빠진다).
     *
     * @param withImage 예전 스크린샷마다 이미지를 함께 보내는지(이미지 묶음이 더 작아 호출이 더 든다). 순서가 우선순위다.
     */
    @Transactional
    public Reservation reserve(long deviceId, List<Boolean> withImage) {
        LocalDate deviceDate = deviceDate();
        LocalDate llmDate = llmDate();
        RemineProperties.Analyze limits = properties.analyze();

        int used = repository.lockDeviceOlderCount(deviceId, deviceDate);
        int items = Math.min(withImage.size(), Math.max(0, limits.dailyOlderLimit() - used));
        if (items == 0) {
            return new Reservation(deviceDate, llmDate, 0, 0);
        }

        int callsLeft = callsLeft(repository.lockLlmCalls(llmDate));
        while (items > 0 && estimateCalls(withImage.subList(0, items)) > callsLeft) {
            items--;
        }
        int calls = estimateCalls(withImage.subList(0, items));
        if (items > 0) {
            repository.addDeviceOlderCount(deviceId, deviceDate, items);
            repository.addLlmCalls(llmDate, calls, 0);
        }
        return new Reservation(deviceDate, llmDate, items, calls);
    }

    /**
     * 분석 뒤 정산. 실패한 장(호출 실패·429·응답 오류·마감)은 기기 몫에서 빼고,
     * 서버 예약은 예상 호출 수를 실제로 성공한 호출 수로 바꾼다(429처럼 거절된 호출은 세지 않는다).
     */
    @Transactional
    public void settle(long deviceId, Reservation reservation, int failedItems, int actualCalls) {
        if (failedItems > 0) {
            repository.addDeviceOlderCount(deviceId, reservation.deviceDate(), -failedItems);
        }
        int diff = actualCalls - reservation.calls();
        if (diff != 0) {
            repository.addLlmCalls(reservation.llmDate(), diff, 0);
        }
    }

    /** 새 스크린샷 분류에 쓴 호출. 막지는 않고 서버 전체 합계에만 더한다. */
    public void recordNewCalls(int calls) {
        if (calls > 0) {
            repository.addLlmCalls(llmDate(), 0, calls);
        }
    }

    /**
     * 오늘 이 기기가 더 보낼 수 있는 예전 스크린샷 장수 = min(기기 남은 몫, 서버 예전 호출 남은 몫 × 묶음당 장수).
     * 묶음당 장수는 보수적으로 이미지 묶음 크기(텍스트보다 작다)를 쓴다.
     */
    public int remainingToday(long deviceId) {
        int deviceLeft = Math.max(0, properties.analyze().dailyOlderLimit()
                - repository.deviceOlderCount(deviceId, deviceDate()));
        long serverLeft = (long) callsLeft(repository.llmCalls(llmDate())) * properties.llm().batch().imageSize();
        return (int) Math.min(deviceLeft, serverLeft);
    }

    /** 기기 몫이 다시 차는 때: 다음 한국 시간 자정. */
    public OffsetDateTime resetsAt() {
        return deviceDate().plusDays(1).atStartOfDay(DEVICE_ZONE).toOffsetDateTime();
    }

    private int callsLeft(LlmCalls used) {
        RemineProperties.Analyze limits = properties.analyze();
        return Math.max(0, Math.min(limits.olderCallCap() - used.older(), limits.dailyLlmCallBudget() - used.total()));
    }

    /** 텍스트만/이미지 포함을 따로 묶으므로 각각 묶음 크기로 올림한 합(빠진 장 단건 재시도는 정산에서 반영). */
    int estimateCalls(List<Boolean> withImage) {
        RemineProperties.Batch batch = properties.llm().batch();
        int images = (int) withImage.stream().filter(Boolean::booleanValue).count();
        int texts = withImage.size() - images;
        return ceilDiv(texts, batch.textSize()) + ceilDiv(images, batch.imageSize());
    }

    private static int ceilDiv(int n, int size) {
        return (n + size - 1) / size;
    }

    private LocalDate deviceDate() {
        return LocalDate.ofInstant(clock.instant(), DEVICE_ZONE);
    }

    private LocalDate llmDate() {
        return LocalDate.ofInstant(clock.instant(), LLM_ZONE);
    }
}
