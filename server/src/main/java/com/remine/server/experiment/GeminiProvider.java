package com.remine.server.experiment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;

/** POST /v1beta/models/{model}:generateContent (JSON mime type). 사고 토큰은 출력 토큰으로 합산한다. */
class GeminiProvider extends JsonHttpProvider {

    private static final String URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent";

    private final String apiKey;

    GeminiProvider(String apiKey, JsonMapper mapper) {
        super(mapper);
        this.apiKey = apiKey;
    }

    @Override
    public LlmReply call(String model, String systemPrompt, String userText) {
        Map<String, Object> body = Map.of(
                "systemInstruction", Map.of("parts", List.of(Map.of("text", systemPrompt))),
                "contents", List.of(Map.of("role", "user", "parts", List.of(Map.of("text", userText)))),
                "generationConfig", Map.of("responseMimeType", "application/json", "maxOutputTokens", 2000));
        JsonNode response = post(URL.formatted(model), Map.of("x-goog-api-key", apiKey), body);

        StringBuilder text = new StringBuilder();
        response.path("candidates").path(0).path("content").path("parts")
                .forEach(part -> text.append(part.path("text").asString("")));
        JsonNode usage = response.path("usageMetadata");
        return new LlmReply(text.toString(),
                usage.path("promptTokenCount").asInt(0),
                usage.path("candidatesTokenCount").asInt(0) + usage.path("thoughtsTokenCount").asInt(0));
    }
}
