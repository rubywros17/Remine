package com.remine.server.experiment;

/**
 * 후보에게 무엇을 보내는지. candidates.json의 "input" 값.
 * TEXT_IMAGE는 모든 표본에 이미지를 보내는 실험 비교용이다. 서비스는 동의한 경우의 짧은 OCR 캡처에만 축소 이미지를 받고 저장하지 않는다.
 */
public enum InputMode {
    TEXT("text"),
    TEXT_IMAGE("text+image");

    private final String json;

    InputMode(String json) {
        this.json = json;
    }

    public String json() {
        return json;
    }

    /** 비어 있으면 text. 알 수 없는 값은 조용히 넘기지 않고 예외로 알린다. */
    public static InputMode parse(String value) {
        if (value == null || value.isBlank()) {
            return TEXT;
        }
        for (InputMode mode : values()) {
            if (mode.json.equalsIgnoreCase(value.trim())) {
                return mode;
            }
        }
        throw new IllegalArgumentException("알 수 없는 input: '" + value + "' (text | text+image)");
    }
}
