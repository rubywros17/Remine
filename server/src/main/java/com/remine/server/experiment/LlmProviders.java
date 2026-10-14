package com.remine.server.experiment;

import tools.jackson.databind.json.JsonMapper;

import java.util.Optional;

/** 후보의 provider 이름과 환경변수 키로 구현체를 만든다. 키가 없으면 비어 있는 Optional. */
final class LlmProviders {

    private LlmProviders() {
    }

    static String envName(String provider) {
        return switch (provider) {
            case "anthropic" -> "ANTHROPIC_API_KEY";
            case "gemini" -> "GEMINI_API_KEY";
            case "openai" -> "OPENAI_API_KEY";
            default -> throw new IllegalArgumentException("알 수 없는 제공사: " + provider);
        };
    }

    static Optional<LlmProvider> create(String provider, JsonMapper mapper) {
        String key = System.getenv(envName(provider));
        if (key == null || key.isBlank()) {
            return Optional.empty();
        }
        return Optional.of(switch (provider) {
            case "anthropic" -> new AnthropicProvider(key, mapper);
            case "gemini" -> new GeminiProvider(key, mapper);
            default -> new OpenAiProvider(key, mapper);
        });
    }
}
