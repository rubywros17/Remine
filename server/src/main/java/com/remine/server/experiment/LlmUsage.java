package com.remine.server.experiment;

/** 한 번의 LLM 호출에서 측정한 토큰 수와 응답 시간. */
public record LlmUsage(int inputTokens, int outputTokens, long latencyMs) {

    public static final LlmUsage NONE = new LlmUsage(0, 0, 0);
}
