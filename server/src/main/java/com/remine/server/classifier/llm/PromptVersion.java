package com.remine.server.classifier.llm;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * 분류 프롬프트 버전. 이전 버전은 지우지 않고 남겨 같은 표본에서 버전끼리 비교할 수 있게 한다.
 * 결과 파일명에 label이 들어간다(예: results.prompt-v1.md).
 */
public enum PromptVersion {
    /** 운영 프롬프트이자 기본값. 처음 실험에서 쓴 문구이며 바뀌면 안 된다. */
    V1("v1"),
    /**
     * 경계 규칙 2개를 더한 실험용 프롬프트. <b>채택 안 됨(사유: SHOPPING 회귀)</b> — 같은 43장에서 하이브리드가
     * −3장(편차 기준선 −1장), 이미지 후보의 SHOPPING→INFO 오답이 3→8건이었다. 재현·비교용 옵션으로만 남긴다.
     * 근거: experiment/SUMMARY.md의 "프롬프트 v2 실험".
     */
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
