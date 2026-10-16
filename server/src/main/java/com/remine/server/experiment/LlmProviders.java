package com.remine.server.experiment;

import tools.jackson.databind.json.JsonMapper;

import java.util.Optional;
import java.util.function.Function;

/**
 * 후보의 provider 이름과 API 키로 구현체를 만든다. 키가 없거나 비어 있으면 비어 있는 Optional.
 * 키는 스프링 Environment에서 읽는다(lookup): 환경변수 GEMINI_API_KEY 또는 ~/.remine.env 파일.
 * 키 값은 어디에도 출력하지 않는다.
 * 제공사를 추가할 때는 {@link #envName}과 {@link #create}의 switch만 늘리면 된다.
 */
final class LlmProviders {

    private LlmProviders() {
    }

    static String envName(String provider) {
        return switch (provider) {
            case "gemini" -> "GEMINI_API_KEY";
            default -> throw new IllegalArgumentException("지원하지 않는 제공사: " + provider);
        };
    }

    /** lookup은 설정 이름 → 값(없으면 null). 실제 실행에서는 {@code environment::getProperty}다. */
    static Optional<LlmProvider> create(Candidate candidate, JsonMapper mapper, Function<String, String> lookup) {
        String key = lookup.apply(envName(candidate.provider()));
        if (key == null || key.isBlank()) {
            return Optional.empty();
        }
        return Optional.of(switch (candidate.provider()) {
            case "gemini" -> new GeminiProvider(key.trim(), candidate.temperature(), mapper);
            default -> throw new IllegalArgumentException("지원하지 않는 제공사: " + candidate.provider());
        });
    }
}
