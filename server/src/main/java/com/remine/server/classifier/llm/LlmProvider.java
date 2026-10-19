package com.remine.server.classifier.llm;

/** 제공사별 HTTP 호출만 담당한다. 프롬프트·파싱은 모든 후보가 공통으로 쓴다. */
public interface LlmProvider {

    LlmReply call(String model, String systemPrompt, String userText);

    /**
     * OCR 텍스트와 함께 이미지(JPEG)를 보내는 호출. 지원하지 않는 제공사는 예외를 던진다.
     * 실험 러너에서만 쓰며, 서비스(앱 → 서버) 경로에서는 이미지를 보내지 않는다.
     */
    default LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
        throw new UnsupportedOperationException("이 제공사는 이미지 입력을 지원하지 않습니다");
    }
}
