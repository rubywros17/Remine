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
        md.append("- 표본이 적어 카테고리별 수치는 편차가 크다. 순위보다 큰 격차와 실패 양상을 본다.\n\n");

        md.append("## 요약\n\n");
        md.append("| 후보 | 정확도 | 평균 응답 | p95 응답 | 장당 비용(USD) | 1,000장 비용(USD) | 파싱 실패 | 호출 실패 |\n");
        md.append("|---|---|---|---|---|---|---|---|\n");
        for (ExperimentStats.Report r : reports) {
            md.append(String.format("| %s | %.1f%% (%d/%d) | %d ms | %d ms | $%.6f | $%.3f | %d | %d |%n",
                    r.candidate().name(), r.accuracy() * 100, r.correct(), r.evaluated(),
                    r.avgLatencyMs(), r.p95LatencyMs(), r.costPerImageUsd(), r.costPerImageUsd() * 1000,
                    r.parseFailed(), r.callFailed()));
        }
        if (!skippedCandidates.isEmpty()) {
            md.append("\n키가 없어 제외한 후보: ").append(String.join(", ", skippedCandidates)).append('\n');
        }

        md.append("\n## 카테고리별 정확도 (맞음/전체)\n\n");
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

        md.append("\n## 자주 틀린 조합 (정답→예측: 건수)\n\n");
        for (ExperimentStats.Report r : reports) {
            String top = r.confusions().entrySet().stream()
                    .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
                    .limit(5)
                    .map(e -> e.getKey() + ": " + e.getValue())
                    .collect(Collectors.joining(", "));
            md.append("- ").append(r.candidate().name()).append(": ").append(top.isEmpty() ? "없음" : top).append('\n');
        }
        md.append("\n> 오답 상세(파일명 포함)는 `errors.local.md`에 있으며 커밋되지 않는다.\n");
        return md.toString();
    }
}
