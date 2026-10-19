package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmOutcome;
import com.remine.server.classifier.llm.LlmUsage;
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
    private final Candidate candidate = new Candidate("test", "gemini", "m", 1.0, 2.0);

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

    private Sample withAlt(Category expected, Category alt, Category predicted) {
        return new Sample("f", expected, alt, predicted, LlmOutcome.Status.OK, true, new LlmUsage(10, 5, 50), "");
    }

    @Test
    void 엄격_허용_명확한_표본_정확도와_애매한_표본_수를_따로_센다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                // 명확한 표본 2장: 1 맞음, 1 틀림
                called(Category.SHOPPING, Category.SHOPPING, 100, 10, 1),
                called(Category.INFO, Category.ETC, 100, 10, 1),
                // 애매한 표본 3장: category 일치 / alt 일치 / 둘 다 불일치
                withAlt(Category.PLACE, Category.SCHEDULE, Category.PLACE),
                withAlt(Category.PLACE, Category.SCHEDULE, Category.SCHEDULE),
                withAlt(Category.PLACE, Category.SCHEDULE, Category.CHAT)));

        assertThat(report.evaluated()).isEqualTo(5);
        assertThat(report.correct()).isEqualTo(2);          // SHOPPING, PLACE(category 일치)
        assertThat(report.lenientCorrect()).isEqualTo(3);   // + alt 일치 1장
        assertThat(report.clearEvaluated()).isEqualTo(2);
        assertThat(report.clearCorrect()).isEqualTo(1);
        assertThat(report.ambiguous()).isEqualTo(3);
        assertThat(report.accuracy()).isCloseTo(0.4, within(1e-9));
        assertThat(report.lenientAccuracy()).isCloseTo(0.6, within(1e-9));
        assertThat(report.clearAccuracy()).isCloseTo(0.5, within(1e-9));
    }

    @Test
    void alt가_없는_2칸_형식_데이터는_엄격과_허용이_같다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                called(Category.CHAT, Category.CHAT, 100, 10, 1),
                called(Category.CHAT, Category.ETC, 100, 10, 1)));

        assertThat(report.ambiguous()).isZero();
        assertThat(report.lenientAccuracy()).isEqualTo(report.accuracy());
        assertThat(report.clearEvaluated()).isEqualTo(report.evaluated());
    }

    @Test
    void 호출_실패한_애매한_표본은_모든_분모에서_빠진다() {
        Sample failed = new Sample("f", Category.PLACE, Category.SCHEDULE, Category.ETC,
                LlmOutcome.Status.CALL_FAILED, true, LlmUsage.NONE, "");

        Report report = ExperimentStats.summarize(candidate, List.of(
                failed, called(Category.PLACE, Category.PLACE, 100, 10, 1)));

        assertThat(report.evaluated()).isEqualTo(1);
        assertThat(report.ambiguous()).isZero();
        assertThat(report.callFailed()).isEqualTo(1);
    }

    @Test
    void results_md에_엄격_허용_명확한_표본_애매한_표본_수가_표시된다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                called(Category.SHOPPING, Category.SHOPPING, 100, 10, 1),
                withAlt(Category.PLACE, Category.SCHEDULE, Category.SCHEDULE)));

        String md = ResultsMarkdown.render(LocalDate.of(2026, 10, 15), 2, 0, List.of(report), List.of());

        assertThat(md).contains("엄격 정확도", "허용 정확도", "명확한 표본 정확도", "애매한 표본 수");
        assertThat(md).contains("50.0% (1/2)")      // 엄격
                .contains("100.0% (2/2)")           // 허용
                .contains("100.0% (1/1)")           // 명확한 표본
                .contains("1 / 2장");               // 애매한 표본 수
    }

    private Sample withChars(Category expected, Category alt, Category predicted, int chars) {
        return new Sample("f", expected, alt, predicted, LlmOutcome.Status.OK, true,
                new LlmUsage(10, 5, 50), "", chars);
    }

    @Test
    void 정답_오답_ETC로_예측한_오답별_평균_OCR_글자_수() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                withChars(Category.SHOPPING, null, Category.SHOPPING, 300),   // 정답
                withChars(Category.PLACE, null, Category.PLACE, 100),         // 정답
                withChars(Category.INFO, null, Category.SHOPPING, 40),        // 오답
                withChars(Category.INFO, null, Category.ETC, 10),            // 오답 + ETC 예측
                withChars(Category.SHOPPING, null, Category.ETC, 20),        // 오답 + ETC 예측
                withChars(Category.PLACE, Category.SCHEDULE, Category.SCHEDULE, 60))); // alt 일치 → 정답(허용)

        assertThat(report.charsCorrect().count()).isEqualTo(3);
        assertThat(report.charsCorrect().average()).isCloseTo((300 + 100 + 60) / 3.0, within(1e-9));
        assertThat(report.charsWrong().count()).isEqualTo(3);
        assertThat(report.charsWrong().average()).isCloseTo((40 + 10 + 20) / 3.0, within(1e-9));
        assertThat(report.charsEtcWrong().count()).isEqualTo(2);
        assertThat(report.charsEtcWrong().average()).isCloseTo(15.0, within(1e-9));
    }

    @Test
    void 글자_수를_모르는_표본과_호출_실패_표본은_글자_수_평균에서_빠진다() {
        Sample unknownChars = called(Category.CHAT, Category.CHAT, 100, 10, 1); // ocrChars = -1
        Sample failed = new Sample("f", Category.CHAT, null, Category.ETC,
                LlmOutcome.Status.CALL_FAILED, true, LlmUsage.NONE, "", 500);

        Report report = ExperimentStats.summarize(candidate, List.of(unknownChars, failed));

        assertThat(report.charsCorrect().count()).isZero();
        assertThat(report.charsWrong().count()).isZero();
    }

    @Test
    void 글자_없는_표본은_0자로_ETC로_예측한_오답에_들어간다() {
        Sample noText = new Sample("f", Category.SHOPPING, null, Category.ETC,
                LlmOutcome.Status.OK, false, LlmUsage.NONE, "", 0);

        Report report = ExperimentStats.summarize(candidate, List.of(noText));

        assertThat(report.charsEtcWrong().count()).isEqualTo(1);
        assertThat(report.charsEtcWrong().average()).isZero();
    }

    @Test
    void 구간_경계는_50자와_150자이고_하한_포함_상한_미포함() {
        assertThat(ExperimentStats.LengthBin.of(0)).isEqualTo(ExperimentStats.LengthBin.SHORT);
        assertThat(ExperimentStats.LengthBin.of(49)).isEqualTo(ExperimentStats.LengthBin.SHORT);
        assertThat(ExperimentStats.LengthBin.of(50)).isEqualTo(ExperimentStats.LengthBin.MEDIUM);
        assertThat(ExperimentStats.LengthBin.of(149)).isEqualTo(ExperimentStats.LengthBin.MEDIUM);
        assertThat(ExperimentStats.LengthBin.of(150)).isEqualTo(ExperimentStats.LengthBin.LONG);
    }

    @Test
    void 글자_수_구간별_엄격_허용_정확도를_센다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                withChars(Category.INFO, null, Category.ETC, 10),                       // SHORT 오답
                withChars(Category.INFO, null, Category.INFO, 30),                      // SHORT 정답
                withChars(Category.PLACE, Category.SCHEDULE, Category.SCHEDULE, 50),   // MEDIUM alt만 일치
                withChars(Category.SHOPPING, null, Category.SHOPPING, 149),             // MEDIUM 정답
                withChars(Category.SHOPPING, null, Category.SHOPPING, 150),             // LONG 정답
                withChars(Category.CHAT, null, Category.CHAT, 400)));                   // LONG 정답

        ExperimentStats.BinScore shortBin = report.byLength().get(ExperimentStats.LengthBin.SHORT);
        ExperimentStats.BinScore mediumBin = report.byLength().get(ExperimentStats.LengthBin.MEDIUM);
        ExperimentStats.BinScore longBin = report.byLength().get(ExperimentStats.LengthBin.LONG);

        assertThat(shortBin).isEqualTo(new ExperimentStats.BinScore(1, 1, 2));
        assertThat(mediumBin).isEqualTo(new ExperimentStats.BinScore(1, 2, 2));
        assertThat(longBin).isEqualTo(new ExperimentStats.BinScore(2, 2, 2));
    }

    @Test
    void 구간별_표에_구간_라벨과_건수가_표시되고_빈_구간은_대시() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                withChars(Category.INFO, null, Category.INFO, 10),
                withChars(Category.INFO, null, Category.ETC, 20)));

        String md = ResultsMarkdown.render(LocalDate.of(2026, 10, 15), 2, 0, List.of(report), List.of());

        assertThat(md).contains("OCR 글자 수 구간별 정확도", "50자 미만", "50자 이상 150자 미만", "150자 이상")
                .contains("50.0% (1/2) · 허용 50.0%");
        assertThat(md).contains("| gemini |".replace("gemini", "test")).contains("| - | - |");
    }

    @Test
    void 글자_수는_공백과_줄바꿈을_뺀_개수() {
        assertThat(Sample.countChars("가나 다\n라\t마")).isEqualTo(5);
        assertThat(Sample.countChars("   \n ")).isZero();
    }

    @Test
    void results_md에_오답_분석_표가_표시된다() {
        Report report = ExperimentStats.summarize(candidate, List.of(
                withChars(Category.SHOPPING, null, Category.SHOPPING, 200),
                withChars(Category.INFO, null, Category.ETC, 12)));

        String md = ResultsMarkdown.render(LocalDate.of(2026, 10, 15), 2, 0, List.of(report), List.of());

        assertThat(md).contains("평균 OCR 글자 수", "ETC로 예측한 오답")
                .contains("평균 200자 (1건)")
                .contains("평균 12자 (1건)");
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
