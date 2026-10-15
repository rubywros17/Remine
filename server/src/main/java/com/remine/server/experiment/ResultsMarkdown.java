package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** results.md 본문. 커밋되는 파일이므로 파일명·OCR 텍스트 없이 집계 수치만 담는다. */
public final class ResultsMarkdown {

    private ResultsMarkdown() {
    }

    private static String avgChars(ExperimentStats.AvgChars chars) {
        return chars.count() == 0 ? "-" : String.format("평균 %.0f자 (%d건)", chars.average(), chars.count());
    }

    public static String render(LocalDate date, int sampleCount, int skippedUnlabeled,
                                List<ExperimentStats.Report> reports, List<String> skippedCandidates) {
        StringBuilder md = new StringBuilder();
        md.append("# LLM 분류 실험 결과\n\n");
        md.append("- 실행일: ").append(date).append('\n');
        md.append("- 표본: ").append(sampleCount).append("장");
        if (skippedUnlabeled > 0) {
            md.append(" (정답 미입력으로 제외 ").append(skippedUnlabeled).append("장)");
        }
        md.append('\n');
        md.append("- **OCR은 앱의 ML Kit이 아니라 Tesseract(kor+eng) 결과라 근사치다.** ")
                .append("실제 앱 텍스트 품질과 다를 수 있다.\n");
        md.append("- 모든 후보가 같은 프롬프트(카테고리 7개 고정, JSON 응답)를 사용했다.\n");
        List<String> imageCandidates = reports.stream().map(r -> r.candidate())
                .filter(Candidate::usesImage).map(Candidate::name).toList();
        if (!imageCandidates.isEmpty()) {
            md.append("- **이미지 입력 후보**: ").append(String.join(", ", imageCandidates))
                    .append(" — OCR 텍스트와 함께 원본 스크린샷을 긴 변 1024px로 줄여 보냈다(실험 러너 전용, 서비스 경로는 이미지를 서버로 보내지 않는다).")
                    .append(" 입력 토큰에 이미지 토큰이 포함되어 있고 글자 없는 스크린샷도 호출했다.\n");
        }
        md.append("- 표본이 적어 카테고리별 수치는 편차가 크다. 순위보다 큰 격차와 실패 양상을 본다.\n\n");

        md.append("## 정확도\n\n");
        md.append("- **엄격**: `category`만 정답으로 인정. **허용**: `category` 또는 `alt`(허용 정답)이면 정답.\n");
        md.append("- **명확한 표본**: `alt`가 없는 표본만의 엄격 정확도. **애매한 표본**: `alt`를 적어 둔 표본 수.\n");
        md.append("- 호출 실패(통신 오류)는 모든 정확도 분모에서 제외한다.\n\n");
        md.append("| 후보 | 엄격 정확도 | 허용 정확도 | 명확한 표본 정확도 | 애매한 표본 수 |\n");
        md.append("|---|---|---|---|---|\n");
        for (ExperimentStats.Report r : reports) {
            md.append(String.format("| %s | %.1f%% (%d/%d) | %.1f%% (%d/%d) | %.1f%% (%d/%d) | %d / %d장 |%n",
                    r.candidate().name(),
                    r.accuracy() * 100, r.correct(), r.evaluated(),
                    r.lenientAccuracy() * 100, r.lenientCorrect(), r.evaluated(),
                    r.clearAccuracy() * 100, r.clearCorrect(), r.clearEvaluated(),
                    r.ambiguous(), r.evaluated()));
        }

        md.append("\n## 속도·비용\n\n");
        md.append("| 후보 | 평균 응답 | p95 응답 | 장당 비용(USD) | 1,000장 비용(USD) | 파싱 실패 | 호출 실패 |\n");
        md.append("|---|---|---|---|---|---|---|\n");
        for (ExperimentStats.Report r : reports) {
            md.append(String.format("| %s | %d ms | %d ms | $%.6f | $%.3f | %d | %d |%n",
                    r.candidate().name(), r.avgLatencyMs(), r.p95LatencyMs(),
                    r.costPerImageUsd(), r.costPerImageUsd() * 1000, r.parseFailed(), r.callFailed()));
        }
        if (!skippedCandidates.isEmpty()) {
            md.append("\n키가 없어 제외한 후보: ").append(String.join(", ", skippedCandidates)).append('\n');
        }

        md.append("\n## 카테고리별 정확도 (엄격, 맞음/전체)\n\n");
        md.append("| 후보 |");
        for (Category c : Category.values()) {
            md.append(' ').append(c).append(" |");
        }
        md.append("\n|---|").append("---|".repeat(Category.values().length)).append('\n');
        for (ExperimentStats.Report r : reports) {
            md.append("| ").append(r.candidate().name()).append(" |");
            for (Category c : Category.values()) {
                ExperimentStats.CategoryScore s = r.perCategory().get(c);
                md.append(' ').append(s == null ? "-" : s.correct() + "/" + s.total()).append(" |");
            }
            md.append('\n');
        }

        md.append("\n## 토큰 사용 (평균)\n\n| 후보 | 입력 | 출력 |\n|---|---|---|\n");
        for (ExperimentStats.Report r : reports) {
            md.append(String.format("| %s | %.0f | %.0f |%n",
                    r.candidate().name(), r.avgInputTokens(), r.avgOutputTokens()));
        }

        md.append("\n## 오답 분석: 평균 OCR 글자 수\n\n");
        md.append("- OCR 텍스트의 **공백 제외 글자 수** 평균이다. 정답·오답은 **허용 기준**(`category` 또는 `alt` 일치)이다.\n");
        md.append("- `ETC로 예측한 오답`은 오답 중 모델이 ETC로 분류한 것(글자가 없어 모델을 부르지 않은 표본 포함)이다.\n");
        md.append("- 오답이 정답보다 글자 수가 뚜렷이 적으면 OCR 품질·글자량이 오답의 원인일 가능성이 크다.\n");
        md.append("- 호출 실패 표본은 제외한다. 표본 수는 괄호 안에 표시한다.\n\n");
        md.append("| 후보 | 정답 | 오답 | ETC로 예측한 오답 |\n|---|---|---|---|\n");
        for (ExperimentStats.Report r : reports) {
            md.append(String.format("| %s | %s | %s | %s |%n", r.candidate().name(),
                    avgChars(r.charsCorrect()), avgChars(r.charsWrong()), avgChars(r.charsEtcWrong())));
        }

        md.append("\n## OCR 글자 수 구간별 정확도\n\n");
        md.append("- 구간은 공백 제외 글자 수 기준이며 `50자 미만` / `50자 이상 150자 미만` / `150자 이상`이다.\n");
        md.append("- 각 칸은 `엄격 정확도 (맞음/전체) · 허용 정확도`이다. 호출 실패·글자 수 미상 표본은 제외한다.\n");
        md.append("- 구간별 표본이 몇 장 안 되므로 비율보다 건수를 함께 본다.\n\n");
        md.append("| 후보 |");
        for (ExperimentStats.LengthBin bin : ExperimentStats.LengthBin.values()) {
            md.append(' ').append(bin.label()).append(" |");
        }
        md.append("\n|---|").append("---|".repeat(ExperimentStats.LengthBin.values().length)).append('\n');
        for (ExperimentStats.Report r : reports) {
            md.append("| ").append(r.candidate().name()).append(" |");
            for (ExperimentStats.LengthBin bin : ExperimentStats.LengthBin.values()) {
                ExperimentStats.BinScore s = r.byLength().get(bin);
                md.append(' ').append(s == null || s.total() == 0 ? "-" : String.format("%.1f%% (%d/%d) · 허용 %.1f%%",
                        100.0 * s.strictCorrect() / s.total(), s.strictCorrect(), s.total(),
                        100.0 * s.lenientCorrect() / s.total())).append(" |");
            }
            md.append('\n');
        }

        md.append("\n## 자주 틀린 조합 (정답→예측: 건수)\n\n");
        for (ExperimentStats.Report r : reports) {
            String top = r.confusions().entrySet().stream()
                    .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
                    .limit(5)
                    .map(e -> e.getKey() + ": " + e.getValue())
                    .collect(Collectors.joining(", "));
            md.append("- ").append(r.candidate().name()).append(": ").append(top.isEmpty() ? "없음" : top).append('\n');
        }
        md.append("\n> 오답 상세(파일명 포함)는 `errors.local.{실행시각}.md`에 있으며 커밋되지 않는다.\n");
        return md.toString();
    }
}
