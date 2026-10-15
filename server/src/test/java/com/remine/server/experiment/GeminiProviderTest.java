package com.remine.server.experiment;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import static org.assertj.core.api.Assertions.assertThat;

/** 공식 문서의 응답 필드명(candidates, usageMetadata, promptFeedback) 기준 샘플로 파싱을 검증한다. */
class GeminiProviderTest {

    private final JsonMapper mapper = JsonMapper.builder().build();

    private LlmReply parse(String json) {
        return GeminiProvider.parse(mapper.readTree(json));
    }

    @Test
    void 요청에_temperature가_generationConfig로_들어간다() {
        JsonNode body = mapper.valueToTree(GeminiProvider.requestBody("시스템", "OCR 텍스트", 0.0));

        JsonNode config = body.path("generationConfig");
        assertThat(config.path("temperature").isNumber()).isTrue();
        assertThat(config.path("temperature").asDouble(-1)).isEqualTo(0.0);
        assertThat(config.path("responseMimeType").asString()).isEqualTo("application/json");
        assertThat(config.path("maxOutputTokens").asInt()).isEqualTo(4096);
        assertThat(body.path("contents").path(0).path("parts").path(0).path("text").asString())
                .isEqualTo("OCR 텍스트");
    }

    @Test
    void 이미지가_없으면_parts에_텍스트만_들어간다() {
        JsonNode body = mapper.valueToTree(GeminiProvider.requestBody("s", "u", 1.0));

        JsonNode parts = body.path("contents").path(0).path("parts");
        assertThat(parts.size()).isEqualTo(1);
        assertThat(parts.path(0).has("inlineData")).isFalse();
    }

    @Test
    void 이미지가_있으면_텍스트_다음에_inlineData_JPEG_base64가_붙는다() {
        byte[] jpeg = {(byte) 0xFF, (byte) 0xD8, 1, 2, 3};

        JsonNode body = mapper.valueToTree(GeminiProvider.requestBody("s", "OCR", 1.0, jpeg));

        JsonNode parts = body.path("contents").path(0).path("parts");
        assertThat(parts.size()).isEqualTo(2);
        assertThat(parts.path(0).path("text").asString()).isEqualTo("OCR"); // 텍스트가 이미지 앞
        assertThat(parts.path(1).path("inlineData").path("mimeType").asString()).isEqualTo("image/jpeg");
        assertThat(parts.path(1).path("inlineData").path("data").asString())
                .isEqualTo(java.util.Base64.getEncoder().encodeToString(jpeg));
        assertThat(body.path("generationConfig").path("temperature").asDouble(-1)).isEqualTo(1.0);
    }

    @Test
    void 후보에서_지정한_temperature가_그대로_전달된다() {
        JsonNode body = mapper.valueToTree(GeminiProvider.requestBody("s", "u", 1.0));

        assertThat(body.path("generationConfig").path("temperature").asDouble(-1)).isEqualTo(1.0);
    }

    @Test
    void 후보의_temperature_기본값은_0이다() {
        assertThat(new Candidate("c", "gemini", "m", 1, 1).temperature()).isEqualTo(0.0);
        assertThat(new Candidate("c", "gemini", "m", 1, 1, 0.7).temperature()).isEqualTo(0.7);
    }

    @Test
    void 정상_응답의_텍스트와_토큰을_꺼낸다() {
        LlmReply reply = parse("""
                {"candidates":[{"content":{"role":"model","parts":[{"text":"{\\"category\\":\\"PLACE\\"}"}]},
                                "finishReason":"STOP"}],
                 "usageMetadata":{"promptTokenCount":120,"candidatesTokenCount":15,"totalTokenCount":135}}
                """);

        assertThat(reply.text()).isEqualTo("{\"category\":\"PLACE\"}");
        assertThat(reply.inputTokens()).isEqualTo(120);
        assertThat(reply.outputTokens()).isEqualTo(15);
        assertThat(reply.note()).isEmpty();
    }

    @Test
    void 사고_토큰은_출력_토큰에_합산한다() {
        LlmReply reply = parse("""
                {"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"STOP"}],
                 "usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":20,"thoughtsTokenCount":300}}
                """);

        assertThat(reply.outputTokens()).isEqualTo(320);
    }

    @Test
    void 여러_part는_이어_붙인다() {
        LlmReply reply = parse("""
                {"candidates":[{"content":{"parts":[{"text":"{\\"a\\":"},{"text":"1}"}]},"finishReason":"STOP"}]}
                """);

        assertThat(reply.text()).isEqualTo("{\"a\":1}");
    }

    @Test
    void 토큰_한도로_잘리면_텍스트는_유지하고_사유를_남긴다() {
        LlmReply reply = parse("""
                {"candidates":[{"content":{"parts":[{"text":"{\\"category\\":\\"SHOP"}]},"finishReason":"MAX_TOKENS"}],
                 "usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":4096}}
                """);

        assertThat(reply.note()).isEqualTo("finishReason=MAX_TOKENS");
        assertThat(reply.text()).startsWith("{\"category\"");
    }

    @Test
    void 후보가_없으면_차단_사유를_남긴다() {
        LlmReply reply = parse("""
                {"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"},"usageMetadata":{"promptTokenCount":30}}
                """);

        assertThat(reply.text()).isEmpty();
        assertThat(reply.note()).contains("PROHIBITED_CONTENT");
        assertThat(reply.inputTokens()).isEqualTo(30);
    }
}
