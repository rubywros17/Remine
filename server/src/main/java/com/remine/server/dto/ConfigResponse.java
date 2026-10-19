package com.remine.server.dto;

import com.remine.server.classifier.RemineProperties;

/** 앱이 알아야 하는 서버 정책값. 모두 RemineProperties에서 읽는다. */
public record ConfigResponse(
        int imageThresholdChars,
        int maxBatchSize,
        long imageMaxBytes,
        int imageMaxLongSide,
        String imageContentType,
        long maxRequestBytes) {

    public static ConfigResponse from(RemineProperties p) {
        return new ConfigResponse(p.llm().imageThresholdChars(), p.analyze().maxBatchSize(),
                p.image().maxBytes(), p.image().maxLongSide(), "image/jpeg", p.image().maxRequestBytes());
    }
}
