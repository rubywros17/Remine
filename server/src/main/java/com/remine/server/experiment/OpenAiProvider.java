package com.remine.server.experiment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;

/** POST /v1/chat/completions (JSON mode). 추론 모델은 추론 토큰도 completion_tokens에 포함되어 과금된다. */
class OpenAiProvider extends JsonHttpProvider {

    private static final String URL = "https://api.openai.com/v1/chat/completions";

    private final String apiKey;

    OpenAiProvider(String apiKey, JsonMapper mapper) {
        super(mapper);
        this.apiKey = apiKey;
    }

    @Override
    public LlmReply call(String model, String systemPrompt, String userText) {
        Map<String, Object> body = Map.of(
                "model", model,
                "max_completion_tokens", 2000,
                "response_format", Map.of("type", "json_object"),
                "messages", List.of(
                        Map.of("role", "system", "content", systemPrompt),
                        Map.of("role", "user", "content", userText)));
        JsonNode response = post(URL, Map.of("Authorization", "Bearer " + apiKey), body);

        return new LlmReply(
                response.path("choices").path(0).path("message").path("content").asString(""),
                response.path("usage").path("prompt_tokens").asInt(0),
                response.path("usage").path("completion_tokens").asInt(0));
    }
}
