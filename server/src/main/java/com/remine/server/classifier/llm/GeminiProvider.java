package com.remine.server.classifier.llm;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;

/**
 * POST /v1beta/models/{model}:generateContent — 형식은 공식 문서(2026-10-14) 기준.
 * 요청: contents[].parts[].text, systemInstruction, generationConfig.{responseMimeType, maxOutputTokens, temperature}
 * 응답: candidates[].content.parts[].text / finishReason, usageMetadata.{promptTokenCount,
 * candidatesTokenCount, thoughtsTokenCount}, 후보가 없으면 promptFeedback.blockReason.
 * thinkingConfig는 문서에서 필드명을 확인하지 못해 보내지 않고 모델 기본값으로 둔다.
 */
public class GeminiProvider extends JsonHttpProvider {

    private static final String URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent";
    // 사고 토큰도 출력 한도를 쓸 수 있어 JSON이 잘리지 않도록 여유를 둔다.
    private static final int MAX_OUTPUT_TOKENS = 4096;

    private final String apiKey;
    private final double temperature;

    public GeminiProvider(String apiKey, double temperature, JsonMapper mapper) {
        super(mapper);
        this.apiKey = apiKey;
        this.temperature = temperature;
    }

    @Override
    public LlmReply call(String model, String systemPrompt, String userText) {
        return parse(post(URL.formatted(model), Map.of("x-goog-api-key", apiKey),
                requestBody(systemPrompt, userText, temperature)));
    }

    @Override
    public LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
        return parse(post(URL.formatted(model), Map.of("x-goog-api-key", apiKey),
                requestBody(systemPrompt, userText, temperature, jpegImage)));
    }

    /** generationConfig.temperature는 후보별 설정값(기본 0)이다. 분류 결과의 재현성을 위해 항상 보낸다. */
    static Map<String, Object> requestBody(String systemPrompt, String userText, double temperature) {
        return requestBody(systemPrompt, userText, temperature, null);
    }

    /**
     * jpegImage가 있으면 같은 user 메시지의 parts에 텍스트 다음으로 inlineData(JPEG, base64)를 붙인다.
     * (문서는 이미지 한 장과 텍스트를 함께 줄 때 텍스트를 이미지 앞에 두라고 권장한다.)
     */
    static Map<String, Object> requestBody(String systemPrompt, String userText, double temperature,
                                           byte[] jpegImage) {
        List<Object> parts = new ArrayList<>();
        parts.add(Map.of("text", userText));
        if (jpegImage != null) {
            parts.add(Map.of("inlineData", Map.of(
                    "mimeType", "image/jpeg",
                    "data", Base64.getEncoder().encodeToString(jpegImage))));
        }
        return Map.of(
                "systemInstruction", Map.of("parts", List.of(Map.of("text", systemPrompt))),
                "contents", List.of(Map.of("role", "user", "parts", parts)),
                "generationConfig", Map.of(
                        "responseMimeType", "application/json",
                        "maxOutputTokens", MAX_OUTPUT_TOKENS,
                        "temperature", temperature));
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
