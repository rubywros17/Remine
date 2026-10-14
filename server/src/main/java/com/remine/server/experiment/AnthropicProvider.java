package com.remine.server.experiment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;

/** POST /v1/messages */
class AnthropicProvider extends JsonHttpProvider {

    private static final String URL = "https://api.anthropic.com/v1/messages";

    private final String apiKey;

    AnthropicProvider(String apiKey, JsonMapper mapper) {
        super(mapper);
        this.apiKey = apiKey;
    }

    @Override
    public LlmReply call(String model, String systemPrompt, String userText) {
        Map<String, Object> body = Map.of(
                "model", model,
                "max_tokens", 400,
                "system", systemPrompt,
                "messages", List.of(Map.of("role", "user", "content", userText)));
        JsonNode response = post(URL,
                Map.of("x-api-key", apiKey, "anthropic-version", "2023-06-01"), body);

        StringBuilder text = new StringBuilder();
        response.path("content").forEach(block -> text.append(block.path("text").asString("")));
        return new LlmReply(text.toString(),
                response.path("usage").path("input_tokens").asInt(0),
                response.path("usage").path("output_tokens").asInt(0));
    }
}
