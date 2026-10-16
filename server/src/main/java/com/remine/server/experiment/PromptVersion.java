package com.remine.server.experiment;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 분류 프롬프트 버전. 이전 버전은 지우지 않고 남겨 같은 표본에서 버전끼리 비교할 수 있게 한다.
 * 결과 파일명에 label이 들어간다(예: results.prompt-v1.md).
 */
public enum PromptVersion {
    V1("v1"),
    V2("v2");

    private final String label;

    PromptVersion(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }

    /** 비어 있으면 v1. 모르는 값은 조용히 넘기지 않고 사용 가능한 목록과 함께 예외로 알린다. */
    public static PromptVersion parse(String value) {
        if (value == null || value.isBlank()) {
            return V1;
        }
        for (PromptVersion version : values()) {
            if (version.label.equalsIgnoreCase(value.trim())) {
                return version;
            }
        }
        throw new IllegalArgumentException("알 수 없는 프롬프트 버전: '" + value + "' / 사용 가능: "
                + Arrays.stream(values()).map(PromptVersion::label).collect(Collectors.joining(", ")));
    }
}
