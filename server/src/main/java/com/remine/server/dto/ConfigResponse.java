package com.remine.server.dto;

import com.remine.server.classifier.RemineProperties;

import java.time.OffsetDateTime;

/**
 * 앱이 알아야 하는 서버 정책값. 정책값은 모두 RemineProperties에서 읽는다.
 * olderRemainingToday·olderResetsAt은 기기별 값이라 X-Device-Id가 있을 때만 채우고, 없거나 모르는 기기면 null이다.
 */
public record ConfigResponse(
        int imageThresholdChars,
        int maxBatchSize,
        long imageMaxBytes,
        int imageMaxLongSide,
        String imageContentType,
        long maxRequestBytes,
        long classifyIntervalMs,
        /* 예전 스크린샷(기기 등록 전에 찍힘) 기기당 하루 분석 장수. */
        int dailyOlderLimit,
        /* 오늘 이 기기가 더 보낼 수 있는 예전 스크린샷 장수(서버 전체 예산이 모자라면 더 적다). */
        Integer olderRemainingToday,
        /* 기기 몫이 다시 차는 때(다음 한국 시간 자정). */
        OffsetDateTime olderResetsAt) {

    public static ConfigResponse from(RemineProperties p) {
        return from(p, null, null);
    }

    public static ConfigResponse from(RemineProperties p, Integer olderRemainingToday, OffsetDateTime olderResetsAt) {
        return new ConfigResponse(p.llm().imageThresholdChars(), p.analyze().maxBatchSize(),
                p.image().maxBytes(), p.image().maxLongSide(), "image/jpeg", p.image().maxRequestBytes(),
                classifyIntervalMs(p), p.analyze().dailyOlderLimit(), olderRemainingToday, olderResetsAt);
    }

    /**
     * 캡처 한 장을 분류하는 데 걸리는 최소 간격(ms). 앱이 남은 시간을 처음부터 예상하는 데 쓴다.
     * 실제 LLM(gemini)은 호출 간격 설정을 따르고, 가짜 분류기는 대기가 없어 0이다.
     */
    private static long classifyIntervalMs(RemineProperties p) {
        return p.classifier() == RemineProperties.ClassifierType.GEMINI ? p.llm().gemini().minIntervalMs() : 0;
    }
}
