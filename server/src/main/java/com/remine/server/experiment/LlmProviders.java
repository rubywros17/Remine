package com.remine.server.experiment;

import tools.jackson.databind.json.JsonMapper;

import java.util.Optional;

/**
 * 후보의 provider 이름과 환경변수 키로 구현체를 만든다. 키가 없으면 비어 있는 Optional.
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

    static Optional<LlmProvider> create(Candidate candidate, JsonMapper mapper) {
        String key = System.getenv(envName(candidate.provider()));
        if (key == null || key.isBlank()) {
            return Optional.empty();
        }
        return Optional.of(switch (candidate.provider()) {
            case "gemini" -> new GeminiProvider(key, candidate.temperature(), mapper);
            default -> throw new IllegalArgumentException("지원하지 않는 제공사: " + candidate.provider());
        });
    }
}
