package com.remine.server.experiment;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

import static org.assertj.core.api.Assertions.assertThat;

/** 공식 문서의 응답 필드명(candidates, usageMetadata, promptFeedback) 기준 샘플로 파싱을 검증한다. */
class GeminiProviderTest {

    private final JsonMapper mapper = JsonMapper.builder().build();

    private LlmReply parse(String json) {
        return GeminiProvider.parse(mapper.readTree(json));
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
