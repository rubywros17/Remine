package com.remine.server.experiment;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ExperimentRunnerSelectionTest {

    private final Candidate lite = new Candidate("gemini-3.5-flash-lite", "gemini", "gemini-3.5-flash-lite", 0.3, 2.5);
    private final Candidate flash = new Candidate("gemini-3.8-flash", "gemini", "gemini-3.8-flash", 0.75, 3.75);
    private final List<Candidate> available = List.of(lite, flash);

    private ExperimentStats.Report reportOf(Candidate candidate) {
        return ExperimentStats.summarize(candidate, List.of());
    }

    @Test
    void 지정이_없으면_전체_후보() {
        assertThat(ExperimentRunner.filterCandidates(available, "")).containsExactly(lite, flash);
        assertThat(ExperimentRunner.filterCandidates(available, null)).containsExactly(lite, flash);
    }

    @Test
    void 모델_ID로_특정_후보만_고른다() {
        assertThat(ExperimentRunner.filterCandidates(available, "gemini-3.8-flash")).containsExactly(flash);
    }

    @Test
    void 쉼표로_여러_개를_지정하고_대소문자와_공백을_무시한다() {
        assertThat(ExperimentRunner.filterCandidates(available, " Gemini-3.8-Flash , gemini-3.5-flash-lite "))
                .containsExactly(flash, lite);
    }

    @Test
    void 모르는_ID가_있으면_사용_가능한_목록과_함께_예외() {
        assertThatThrownBy(() -> ExperimentRunner.filterCandidates(available, "gemini-9"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("gemini-9")
                .hasMessageContaining("gemini-3.5-flash-lite");
    }

    @Test
    void 결과_파일명은_제한_실행_후보_지정_실행_전체_실행에_따라_다르다() {
        List<ExperimentStats.Report> one = List.of(reportOf(flash));

        assertThat(ExperimentRunner.resultsFileName(false, false, List.of(reportOf(lite), reportOf(flash))))
                .isEqualTo("results.md");
        assertThat(ExperimentRunner.resultsFileName(true, false, one)).isEqualTo("results.limit.md");
        assertThat(ExperimentRunner.resultsFileName(true, true, one)).isEqualTo("results.limit.md");
        assertThat(ExperimentRunner.resultsFileName(false, true, one)).isEqualTo("results.gemini-3.8-flash.md");
    }
}
