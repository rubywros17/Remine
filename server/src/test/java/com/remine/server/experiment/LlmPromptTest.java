package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class LlmPromptTest {

    private final JsonMapper mapper = JsonMapper.builder().build();

    @Test
    void 정상_JSON을_파싱한다() {
        LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper,
                "{\"category\":\"SHOPPING\",\"tags\":[\"가디건\",\" 니트 \"],\"summary\":\"니트 가디건 구매\"}");

        assertThat(parsed.ok()).isTrue();
        assertThat(parsed.result().category()).isEqualTo(Category.SHOPPING);
        assertThat(parsed.result().tags()).containsExactly("가디건", "니트");
        assertThat(parsed.result().summary()).isEqualTo("니트 가디건 구매");
    }

    @Test
    void 코드펜스와_앞뒤_설명이_붙어도_JSON만_꺼낸다() {
        String raw = "분류 결과입니다.\n```json\n{\"category\": \"place\", \"tags\": [], \"summary\": \"\"}\n```";

        LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper, raw);

        assertThat(parsed.ok()).isTrue();
        assertThat(parsed.result().category()).isEqualTo(Category.PLACE);
    }

    @Test
    void 범위_밖_카테고리는_ETC와_실패로_처리한다() {
        LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper, "{\"category\":\"FOOD\",\"tags\":[],\"summary\":\"\"}");

        assertThat(parsed.ok()).isFalse();
        assertThat(parsed.result().category()).isEqualTo(Category.ETC);
    }

    @Test
    void JSON이_아니면_ETC와_실패로_처리한다() {
        assertThat(LlmPrompt.parse(mapper, "잘 모르겠습니다").ok()).isFalse();
        assertThat(LlmPrompt.parse(mapper, "{\"category\": ").ok()).isFalse();
    }

    @Test
    void 프롬프트에_카테고리_7개_정의가_모두_들어_있다() {
        assertThat(LlmPrompt.DEFINITIONS).hasSize(Category.values().length);
        LlmPrompt.DEFINITIONS.forEach((category, definition) ->
                assertThat(LlmPrompt.SYSTEM).contains("- " + category + ": " + definition));
    }

    @Test
    void README_라벨링_표가_프롬프트_정의와_같다() throws IOException {
        // gradle test의 작업 디렉터리는 server/ 이다.
        String readme = Files.readString(Path.of("../experiment/README.md"), StandardCharsets.UTF_8);

        LlmPrompt.DEFINITIONS.forEach((category, definition) ->
                assertThat(readme).contains("| `" + category + "` | " + definition + " |"));
    }

    @Test
    void OCR_텍스트는_길이를_제한한다() {
        String user = LlmPrompt.user("가".repeat(10_000));

        assertThat(user.length()).isLessThan(3100);
    }
}
