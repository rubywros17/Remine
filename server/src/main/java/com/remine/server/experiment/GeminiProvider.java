package com.remine.server.experiment;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;

/**
 * POST /v1beta/models/{model}:generateContent — 형식은 공식 문서(2026-10-14) 기준.
 * 요청: contents[].parts[].text, systemInstruction, generationConfig.{responseMimeType, maxOutputTokens}
 * 응답: candidates[].content.parts[].text / finishReason, usageMetadata.{promptTokenCount,
 * candidatesTokenCount, thoughtsTokenCount}, 후보가 없으면 promptFeedback.blockReason.
 * thinkingConfig는 문서에서 필드명을 확인하지 못해 보내지 않고 모델 기본값으로 둔다.
 */
class GeminiProvider extends JsonHttpProvider {

    private static final String URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent";
    // 사고 토큰도 출력 한도를 쓸 수 있어 JSON이 잘리지 않도록 여유를 둔다.
    private static final int MAX_OUTPUT_TOKENS = 4096;

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
                "generationConfig", Map.of(
                        "responseMimeType", "application/json",
                        "maxOutputTokens", MAX_OUTPUT_TOKENS));
        return parse(post(URL.formatted(model), Map.of("x-goog-api-key", apiKey), body));
    }

    /**
     * 응답 JSON → LlmReply. 출력 토큰은 사고 토큰을 합산한다(사고 토큰은 출력으로 과금).
     * 정상 종료(STOP)가 아니거나 후보가 없으면 사유를 note에 남긴다.
     */
    static LlmReply parse(JsonNode response) {
        JsonNode usage = response.path("usageMetadata");
        int input = usage.path("promptTokenCount").asInt(0);
        int output = usage.path("candidatesTokenCount").asInt(0) + usage.path("thoughtsTokenCount").asInt(0);

        JsonNode candidate = response.path("candidates").path(0);
        if (candidate.isMissingNode()) {
            String reason = response.path("promptFeedback").path("blockReason").asString("알 수 없음");
            return new LlmReply("", input, output, "후보 없음 (blockReason=" + reason + ")");
        }

        StringBuilder text = new StringBuilder();
        candidate.path("content").path("parts").forEach(part -> text.append(part.path("text").asString("")));

        String finishReason = candidate.path("finishReason").asString("");
        String note = finishReason.isEmpty() || finishReason.equals("STOP") ? "" : "finishReason=" + finishReason;
        return new LlmReply(text.toString(), input, output, note);
    }
}
