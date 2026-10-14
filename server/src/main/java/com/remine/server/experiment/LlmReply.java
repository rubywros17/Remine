package com.remine.server.experiment;

/** 제공사 응답에서 꺼낸 모델 출력 텍스트와 토큰 수. */
public record LlmReply(String text, int inputTokens, int outputTokens) {
}
