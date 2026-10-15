package com.remine.server.experiment;

/**
 * 후보에게 무엇을 보내는지. candidates.json의 "input" 값.
 * TEXT_IMAGE는 실험 러너 전용이다. 앱은 원본 이미지를 서버로 보내지 않는다는 원칙을 유지한다.
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
