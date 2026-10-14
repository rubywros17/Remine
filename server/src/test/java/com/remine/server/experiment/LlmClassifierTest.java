package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

class LlmClassifierTest {

    private final JsonMapper mapper = JsonMapper.builder().build();
    private final Candidate candidate = new Candidate("c", "gemini", "m", 1, 1);

    @Test
    void 응답을_분류_결과와_토큰으로_변환한다() {
        LlmProvider provider = (model, system, user) -> new LlmReply(
                "{\"category\":\"MOVIE_DRAMA\",\"tags\":[\"드라마\"],\"summary\":\"드라마 정보\"}", 120, 20);

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("드라마 시즌2");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(outcome.result().category()).isEqualTo(Category.MOVIE_DRAMA);
        assertThat(outcome.usage().inputTokens()).isEqualTo(120);
        assertThat(outcome.usage().outputTokens()).isEqualTo(20);
    }

    @Test
    void 이해할_수_없는_응답은_PARSE_FAILED() {
        LlmProvider provider = (model, system, user) -> new LlmReply("모르겠어요", 10, 3);

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.PARSE_FAILED);
        assertThat(outcome.result().category()).isEqualTo(Category.ETC);
    }

    @Test
    void 호출이_한_번_실패해도_재시도해서_성공하면_OK() {
        AtomicInteger calls = new AtomicInteger();
        LlmProvider provider = (model, system, user) -> {
            if (calls.incrementAndGet() == 1) {
                throw new IllegalStateException("429");
            }
            return new LlmReply("{\"category\":\"CHAT\",\"tags\":[],\"summary\":\"\"}", 5, 5);
        };

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("ㅋㅋ");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(calls.get()).isEqualTo(2);
    }
}
