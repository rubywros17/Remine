package com.remine.server.experiment;

/**
 * 제공사 응답에서 꺼낸 모델 출력 텍스트와 토큰 수.
 * note는 비정상 종료 사유(차단, 토큰 한도 등)이고 정상이면 빈 문자열이다.
 */
public record LlmReply(String text, int inputTokens, int outputTokens, String note) {

    public LlmReply(String text, int inputTokens, int outputTokens) {
        this(text, inputTokens, outputTokens, "");
    }
}
