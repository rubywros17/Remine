package com.remine.server.classifier.llm;

/** user 메시지의 조각 하나: 텍스트 또는 JPEG 이미지(둘 중 하나만 null이 아니다). 배치 요청이 여러 조각을 순서대로 보낸다. */
public record LlmPart(String text, byte[] jpegImage) {

    public static LlmPart text(String text) {
        return new LlmPart(text, null);
    }

    public static LlmPart image(byte[] jpegImage) {
        return new LlmPart(null, jpegImage);
    }
}
