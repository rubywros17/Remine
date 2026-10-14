package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.Report;
import com.remine.server.experiment.ExperimentStats.Sample;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class ExperimentStatsTest {

    // 입력 $1 / 출력 $2 per 1M tokens
    private final Candidate candidate = new Candidate("test", "openai", "m", 1.0, 2.0);

    private Sample called(Category expected, Category predicted, long latencyMs, int in, int out) {
        return new Sample("f", expected, predicted, LlmOutcome.Status.OK, true, new LlmUsage(in, out, latencyMs));
    }

    @Test
    void 정확도와_카테고리별_점수를_계산한다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                called(Category.SHOPPING, Category.SHOPPING, 100, 100, 10),
                called(Category.SHOPPING, Category.ETC, 200, 100, 10),
                called(Category.PLACE, Category.PLACE, 300, 100, 10)));

        assertThat(report.accuracy()).isCloseTo(2.0 / 3, within(1e-9));
        assertThat(report.perCategory().get(Category.SHOPPING).correct()).isEqualTo(1);
        assertThat(report.perCategory().get(Category.SHOPPING).total()).isEqualTo(2);
        assertThat(report.confusions()).containsEntry("SHOPPING→ETC", 1);
    }

    @Test
    void 장당_비용은_평균_토큰과_단가로_계산한다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                called(Category.INFO, Category.INFO, 100, 1000, 100),
                called(Category.INFO, Category.INFO, 100, 3000, 300)));

        assertThat(report.avgInputTokens()).isEqualTo(2000);
        assertThat(report.avgOutputTokens()).isEqualTo(200);
        // (2000 * 1 + 200 * 2) / 1,000,000
        assertThat(report.costPerImageUsd()).isCloseTo(0.0024, within(1e-12));
    }

    @Test
    void 평균과_p95_응답시간() {
        List<Sample> samples = new ArrayList<>();
        for (int i = 1; i <= 20; i++) {
            samples.add(called(Category.ETC, Category.ETC, i * 10L, 10, 1));
        }

        Report report = ExperimentStats.summarize(candidate, samples);

        assertThat(report.avgLatencyMs()).isEqualTo(105);
        assertThat(report.p95LatencyMs()).isEqualTo(190); // ceil(0.95 * 20) = 19번째
    }

    @Test
    void 호출_실패는_정확도에서_빼고_파싱_실패는_오답으로_센다() {
        Sample callFailed = new Sample("f", Category.CHAT, Category.ETC,
                LlmOutcome.Status.CALL_FAILED, true, LlmUsage.NONE);
        Sample parseFailed = new Sample("f", Category.CHAT, Category.ETC,
                LlmOutcome.Status.PARSE_FAILED, true, new LlmUsage(10, 5, 50));

        Report report = ExperimentStats.summarize(candidate, List.of(
                callFailed, parseFailed, called(Category.CHAT, Category.CHAT, 80, 10, 5)));

        assertThat(report.callFailed()).isEqualTo(1);
        assertThat(report.parseFailed()).isEqualTo(1);
        assertThat(report.evaluated()).isEqualTo(2);
        assertThat(report.accuracy()).isEqualTo(0.5);
    }

    @Test
    void 글자_없는_샘플은_정확도에는_포함하고_시간과_비용_평균에서는_뺀다() {
        Sample noText = new Sample("f", Category.ETC, Category.ETC, LlmOutcome.Status.OK, false, LlmUsage.NONE);

        Report report = ExperimentStats.summarize(candidate, List.of(
                noText, called(Category.PLACE, Category.PLACE, 400, 500, 50)));

        assertThat(report.evaluated()).isEqualTo(2);
        assertThat(report.avgLatencyMs()).isEqualTo(400);
        assertThat(report.avgInputTokens()).isEqualTo(500);
    }

    @Test
    void results_md에는_파일명이_들어가지_않는다() {
        Sample sample = new Sample("secret_screenshot.jpg", Category.SHOPPING, Category.ETC,
                LlmOutcome.Status.OK, true, new LlmUsage(10, 5, 50));
        Report report = ExperimentStats.summarize(candidate, List.of(sample));

        String md = ResultsMarkdown.render(LocalDate.of(2026, 10, 14), 1, 0, List.of(report), List.of());

        assertThat(md).doesNotContain("secret_screenshot").contains("Tesseract").contains("SHOPPING→ETC");
    }
}
