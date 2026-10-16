package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.LengthBin;
import com.remine.server.experiment.RunComparison.Change;
import com.remine.server.experiment.RunComparison.Score;
import com.remine.server.experiment.RunCsv.Row;
import com.remine.server.experiment.RunCsv.Run;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class RunComparisonTest {

    private Row row(String file, Category expected, Category predicted, int chars) {
        return new Row(file, expected, null, predicted, LlmOutcome.Status.OK, true, chars);
    }

    private Row failed(String file, Category expected, int chars) {
        return new Row(file, expected, null, Category.ETC, LlmOutcome.Status.CALL_FAILED, true, chars);
    }

    private Run run(PromptVersion version, String candidate, Row... rows) {
        return new Run(candidate, version, "20261016-100000", List.of(rows));
    }

    @Test
    void 정확도는_호출_실패를_분모에서_뺀다() {
        Run run = run(PromptVersion.V1, "c",
                row("a", Category.INFO, Category.INFO, 10),
                row("b", Category.INFO, Category.SHOPPING, 10),
                failed("c", Category.INFO, 10));

        assertThat(RunComparison.accuracy(run)).isEqualTo(new Score(1, 2));
    }

    @Test
    void 카테고리별_글자수_구간별_집계() {
        Run run = run(PromptVersion.V1, "c",
                row("a", Category.INFO, Category.INFO, 10),
                row("b", Category.INFO, Category.SHOPPING, 60),
                row("c", Category.SHOPPING, Category.SHOPPING, 200));

        assertThat(RunComparison.byCategory(run).get(Category.INFO)).isEqualTo(new Score(1, 2));
        assertThat(RunComparison.byCategory(run).get(Category.SHOPPING)).isEqualTo(new Score(1, 1));
        assertThat(RunComparison.byLength(run).get(LengthBin.SHORT)).isEqualTo(new Score(1, 1));
        assertThat(RunComparison.byLength(run).get(LengthBin.MEDIUM)).isEqualTo(new Score(0, 1));
        assertThat(RunComparison.byLength(run).get(LengthBin.LONG)).isEqualTo(new Score(1, 1));
    }

    @Test
    void 하이브리드는_기준_글자_수_이상이면_텍스트_미만이면_이미지_결과를_쓴다() {
        // a: 150자 이상 → 텍스트 결과(맞음), b: 149자 → 이미지 결과(맞음), c: 짧음 → 이미지 결과(틀림)
        Run text = run(PromptVersion.V1, "t",
                row("a", Category.INFO, Category.INFO, 150),
                row("b", Category.INFO, Category.ETC, 149),
                row("c", Category.INFO, Category.INFO, 10));
        Run image = run(PromptVersion.V1, "t+image",
                row("a", Category.INFO, Category.ETC, 150),
                row("b", Category.INFO, Category.INFO, 149),
                row("c", Category.INFO, Category.SHOPPING, 10));

        assertThat(RunComparison.hybrid(text, image, 150)).isEqualTo(new Score(2, 3));
    }

    @Test
    void 하이브리드에서_선택된_쪽이_호출_실패면_그_표본은_제외한다() {
        Run text = run(PromptVersion.V1, "t",
                row("a", Category.INFO, Category.INFO, 200),
                row("b", Category.INFO, Category.INFO, 10));
        Run image = run(PromptVersion.V1, "t+image",
                row("a", Category.INFO, Category.ETC, 200),
                failed("b", Category.INFO, 10));

        assertThat(RunComparison.hybrid(text, image, 150)).isEqualTo(new Score(1, 1));
    }

    @Test
    void 고쳐진_것과_새로_틀린_것을_표본_단위로_분류한다() {
        Run base = run(PromptVersion.V1, "c",
                row("fixed", Category.INFO, Category.SHOPPING, 10),
                row("regressed", Category.SHOPPING, Category.SHOPPING, 10),
                row("right", Category.INFO, Category.INFO, 10),
                row("wrong", Category.PLACE, Category.INFO, 10),
                row("onlyBase", Category.INFO, Category.INFO, 10),
                failed("failedInNext", Category.INFO, 10));
        Run next = run(PromptVersion.V2, "c",
                row("fixed", Category.INFO, Category.INFO, 10),
                row("regressed", Category.SHOPPING, Category.INFO, 10),
                row("right", Category.INFO, Category.INFO, 10),
                row("wrong", Category.PLACE, Category.SCHEDULE, 10),
                row("failedInNext", Category.INFO, Category.INFO, 10));

        List<RunComparison.Transition> ts = RunComparison.transitions(base, next);

        assertThat(ts).hasSize(4); // 한쪽에만 있거나 호출 실패한 표본은 짝을 지을 수 없어 제외
        assertThat(RunComparison.count(ts, Change.FIXED)).isEqualTo(1);
        assertThat(RunComparison.count(ts, Change.REGRESSED)).isEqualTo(1);
        assertThat(RunComparison.count(ts, Change.STILL_RIGHT)).isEqualTo(1);
        assertThat(RunComparison.count(ts, Change.STILL_WRONG)).isEqualTo(1);
        assertThat(RunComparison.typeCounts(ts, Change.FIXED)).containsExactly(Map.entry("INFO: SHOPPING → INFO", 1L));
        assertThat(RunComparison.typeCounts(ts, Change.REGRESSED)).containsExactly(Map.entry("SHOPPING: SHOPPING → INFO", 1L));
    }

    @Test
    void 커밋용_요약에는_파일명이_없고_로컬_목록에만_파일명이_있다() {
        Run base = run(PromptVersion.V1, "cand",
                row("secret_capture.jpg", Category.INFO, Category.SHOPPING, 40),
                row("other.jpg", Category.INFO, Category.INFO, 300));
        Run next = run(PromptVersion.V2, "cand",
                row("secret_capture.jpg", Category.INFO, Category.INFO, 40),
                row("other.jpg", Category.INFO, Category.INFO, 300));
        Map<String, Run[]> runs = new LinkedHashMap<>();
        runs.put("cand", new Run[]{base, next});
        List<RunComparison.Pair> overall = List.of(new RunComparison.Pair("텍스트만 (cand)",
                RunComparison.accuracy(base), RunComparison.accuracy(next)));

        String summary = RunComparison.renderSummary(PromptVersion.V1, PromptVersion.V2, overall, runs, 150);
        String local = RunComparison.renderLocal(PromptVersion.V1, PromptVersion.V2, runs);

        assertThat(summary).doesNotContain("secret_capture")
                .contains("프롬프트 비교: v1 → v2", "50.0% (1/2)", "100.0% (2/2)", "+50.0%p (+1장)", "고쳐짐 1장, 새로 틀림 0장")
                .contains("INFO: SHOPPING → INFO ×1");
        assertThat(local).contains("secret_capture.jpg (40자): INFO, SHOPPING → INFO");
    }
}
