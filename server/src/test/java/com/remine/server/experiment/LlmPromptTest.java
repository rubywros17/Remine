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
    void v2는_v1에_경계_규칙_블록만_더한_프롬프트다() {
        String v1 = LlmPrompt.system(PromptVersion.V1);
        String v2 = LlmPrompt.system(PromptVersion.V2);

        LlmPrompt.RULES_V2.forEach(rule -> assertThat(v2).contains("- " + rule));
        LlmPrompt.DEFINITIONS.forEach((category, definition) ->
                assertThat(v2).contains("- " + category + ": " + definition));
        // 규칙 블록을 빼면 v1과 완전히 같다 (정의·응답 형식은 건드리지 않았다)
        String ruleBlock = "경계가 애매할 때는 위 정의보다 아래 규칙을 우선한다.\n"
                + String.join("\n", LlmPrompt.RULES_V2.stream().map(r -> "- " + r).toList()) + "\n";
        assertThat(v2.replace(ruleBlock, "")).isEqualTo(v1);
        // 규칙은 정의 뒤, 응답 형식 앞에 온다
        assertThat(v2.indexOf("- ETC:")).isLessThan(v2.indexOf("경계가 애매할 때는"));
        assertThat(v2.indexOf("경계가 애매할 때는")).isLessThan(v2.indexOf("응답은 JSON"));
    }

    @Test
    void v2_규칙은_특정_앱이나_캡처를_겨냥하지_않는다() {
        String rules = String.join(" ", LlmPrompt.RULES_V2);

        assertThat(rules).doesNotContainIgnoringCase("instagram")
                .doesNotContain("인스타")
                .doesNotContain("쿠팡")
                .doesNotContain("네이버");
    }

    @Test
    void README의_v2_경계_규칙이_프롬프트_규칙과_같다() throws IOException {
        String readme = Files.readString(Path.of("../experiment/README.md"), StandardCharsets.UTF_8);

        assertThat(readme).contains("프롬프트 v2 경계 규칙");
        LlmPrompt.RULES_V2.forEach(rule -> assertThat(readme).contains("- " + rule));
    }

    @Test
    void 이미지_변형의_user_메시지는_기존_메시지에_한_줄만_더한다() {
        String base = LlmPrompt.user("텍스트");

        assertThat(LlmPrompt.userWithImage("텍스트")).startsWith(base).hasSizeGreaterThan(base.length());
    }

    @Test
    void OCR_텍스트는_길이를_제한한다() {
        String user = LlmPrompt.user("가".repeat(10_000));

        assertThat(user.length()).isLessThan(3100);
    }
}
