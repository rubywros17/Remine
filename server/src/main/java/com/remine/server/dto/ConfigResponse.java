package com.remine.server.dto;

import com.remine.server.classifier.RemineProperties;

/** 앱이 알아야 하는 서버 정책값. 모두 RemineProperties에서 읽는다. */
public record ConfigResponse(
        int imageThresholdChars,
        int maxBatchSize,
        long imageMaxBytes,
        int imageMaxLongSide,
        String imageContentType,
        long maxRequestBytes,
        long classifyIntervalMs) {

    public static ConfigResponse from(RemineProperties p) {
        return new ConfigResponse(p.llm().imageThresholdChars(), p.analyze().maxBatchSize(),
                p.image().maxBytes(), p.image().maxLongSide(), "image/jpeg", p.image().maxRequestBytes(),
                classifyIntervalMs(p));
    }

    /**
     * 캡처 한 장을 분류하는 데 걸리는 최소 간격(ms). 앱이 남은 시간을 처음부터 예상하는 데 쓴다.
     * 실제 LLM(gemini)은 호출 간격 설정을 따르고, 가짜 분류기는 대기가 없어 0이다.
     */
    private static long classifyIntervalMs(RemineProperties p) {
        return p.classifier() == RemineProperties.ClassifierType.GEMINI ? p.llm().gemini().minIntervalMs() : 0;
    }
}
