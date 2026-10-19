package com.remine.server.experiment;

import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.LengthBin;
import com.remine.server.experiment.RunCsv.Row;
import com.remine.server.experiment.RunCsv.Run;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 같은 표본의 두 실행(예: 프롬프트 v1 vs v2)을 비교한다. 정답은 엄격 기준(category만)이고
 * 호출 실패 표본은 모든 분모에서 뺀다. 순수 함수만 있어 단위 테스트한다.
 */
final class RunComparison {

    /** 하이브리드 기본 기준값(공백 제외 OCR 글자 수). SUMMARY의 하이브리드 76.7~79.1%와 같은 방식이다. */
    static final int HYBRID_THRESHOLD_CHARS = 150;

    private RunComparison() {
    }

    record Score(int correct, int total) {
        double rate() {
            return total == 0 ? 0 : (double) correct / total;
        }
    }

    /** 한 표본이 두 실행에서 어떻게 바뀌었는지. */
    enum Change { FIXED, REGRESSED, STILL_RIGHT, STILL_WRONG }

    record Transition(Row base, Row next, Change change) {
    }

    static Score accuracy(Run run) {
        List<Row> evaluated = run.rows().stream().filter(Row::evaluated).toList();
        return new Score((int) evaluated.stream().filter(Row::strictCorrect).count(), evaluated.size());
    }

    static Map<Category, Score> byCategory(Run run) {
        Map<Category, int[]> raw = new EnumMap<>(Category.class);
        for (Row row : run.rows()) {
            if (!row.evaluated()) {
                continue;
            }
            int[] v = raw.computeIfAbsent(row.expected(), c -> new int[2]);
            v[1]++;
            if (row.strictCorrect()) {
                v[0]++;
            }
        }
        Map<Category, Score> scores = new EnumMap<>(Category.class);
        raw.forEach((c, v) -> scores.put(c, new Score(v[0], v[1])));
        return scores;
    }

    static Map<LengthBin, Score> byLength(Run run) {
        Map<LengthBin, int[]> raw = new EnumMap<>(LengthBin.class);
        for (Row row : run.rows()) {
            if (!row.evaluated() || row.ocrChars() < 0) {
                continue;
            }
            int[] v = raw.computeIfAbsent(LengthBin.of(row.ocrChars()), b -> new int[2]);
            v[1]++;
            if (row.strictCorrect()) {
                v[0]++;
            }
        }
        Map<LengthBin, Score> scores = new EnumMap<>(LengthBin.class);
        raw.forEach((b, v) -> scores.put(b, new Score(v[0], v[1])));
        return scores;
    }

    /**
     * 하이브리드: OCR 글자 수가 기준값 이상이면 텍스트 실행의 결과, 미만이면 이미지 실행의 결과를 쓴다.
     * 선택된 쪽이 호출 실패면 그 표본은 제외한다. 글자 수는 텍스트 실행 기준이다(두 실행이 같은 OCR을 쓴다).
     */
    static Score hybrid(Run text, Run image, int thresholdChars) {
        Map<String, Row> imageRows = new HashMap<>();
        image.rows().forEach(row -> imageRows.put(row.filename(), row));
        int correct = 0;
        int total = 0;
        for (Row textRow : text.rows()) {
            Row chosen = textRow.ocrChars() >= thresholdChars ? textRow : imageRows.get(textRow.filename());
            if (chosen == null || !chosen.evaluated()) {
                continue;
            }
            total++;
            if (chosen.strictCorrect()) {
                correct++;
            }
        }
        return new Score(correct, total);
    }

    /** 두 실행에서 모두 평가된 표본만 짝지어 변화를 분류한다. */
    static List<Transition> transitions(Run base, Run next) {
        Map<String, Row> nextRows = new HashMap<>();
        next.rows().forEach(row -> nextRows.put(row.filename(), row));
        List<Transition> result = new ArrayList<>();
        for (Row b : base.rows()) {
            Row n = nextRows.get(b.filename());
            if (n == null || !b.evaluated() || !n.evaluated()) {
                continue;
            }
            Change change = b.strictCorrect()
                    ? (n.strictCorrect() ? Change.STILL_RIGHT : Change.REGRESSED)
                    : (n.strictCorrect() ? Change.FIXED : Change.STILL_WRONG);
            result.add(new Transition(b, n, change));
        }
        return result;
    }

    static long count(List<Transition> transitions, Change change) {
        return transitions.stream().filter(t -> t.change() == change).count();
    }

    /** "정답: 이전 예측 → 새 예측" 유형별 건수(파일명 없음). 많은 순. */
    static Map<String, Long> typeCounts(List<Transition> transitions, Change change) {
        return transitions.stream().filter(t -> t.change() == change)
                .collect(Collectors.groupingBy(
                        t -> t.base().expected() + ": " + t.base().predicted() + " → " + t.next().predicted(),
                        LinkedHashMap::new, Collectors.counting()))
                .entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey()))
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue, (a, b) -> a, LinkedHashMap::new));
    }

    // ---- 마크다운 ----

    /** 한 후보(또는 하이브리드)의 두 버전 비교 한 줄. */
    record Pair(String label, Score base, Score next) {
    }

    /** 커밋해도 되는 집계 리포트(파일명 없음). pairs는 텍스트/이미지/하이브리드 순. */
    static String renderSummary(PromptVersion baseVersion, PromptVersion nextVersion, List<Pair> overall,
                                Map<String, Run[]> runs, int hybridThreshold) {
        String b = baseVersion.label();
        String n = nextVersion.label();
        StringBuilder md = new StringBuilder();
        md.append("# 프롬프트 비교: ").append(b).append(" → ").append(n).append("\n\n");
        md.append("- 같은 표본·같은 정답(`labels.csv`)으로 후보별 **최신 실행**을 비교했다. 정답은 엄격 기준(`category`만), 호출 실패 표본은 제외한다.\n");
        md.append("- 하이브리드는 OCR ").append(hybridThreshold).append("자 이상이면 텍스트 실행, 미만이면 이미지 실행의 결과를 쓴 표본별 합산이다.\n");
        md.append("- temperature 1.0이라 같은 프롬프트도 실행마다 몇 장은 달라질 수 있다. 같은 버전을 두 번 돌린 편차와 함께 해석한다.\n\n");

        md.append("## 전체 정확도\n\n| 입력 | ").append(b).append(" | ").append(n).append(" | 변화 |\n|---|---|---|---|\n");
        for (Pair p : overall) {
            md.append(String.format("| %s | %s | %s | %s |%n", p.label(), score(p.base()), score(p.next()), delta(p.base(), p.next())));
        }

        for (Map.Entry<String, Run[]> e : runs.entrySet()) {
            Run base = e.getValue()[0];
            Run next = e.getValue()[1];
            md.append("\n## ").append(e.getKey()).append("\n\n");
            md.append("실행: ").append(b).append(" ").append(base.timestamp()).append(", ")
                    .append(n).append(" ").append(next.timestamp()).append("\n\n");

            md.append("### 카테고리별 (정답 카테고리 기준 맞음/전체)\n\n| 카테고리 | ").append(b).append(" | ").append(n).append(" |\n|---|---|---|\n");
            Map<Category, Score> bc = byCategory(base);
            Map<Category, Score> nc = byCategory(next);
            for (Category c : Category.values()) {
                if (bc.containsKey(c) || nc.containsKey(c)) {
                    md.append(String.format("| %s | %s | %s |%n", c, plain(bc.get(c)), plain(nc.get(c))));
                }
            }

            md.append("\n### OCR 글자 수 구간별\n\n| 구간 | ").append(b).append(" | ").append(n).append(" |\n|---|---|---|\n");
            Map<LengthBin, Score> bl = byLength(base);
            Map<LengthBin, Score> nl = byLength(next);
            for (LengthBin bin : LengthBin.values()) {
                md.append(String.format("| %s | %s | %s |%n", bin.label(), score(bl.get(bin)), score(nl.get(bin))));
            }

            List<Transition> ts = transitions(base, next);
            md.append(String.format("%n### 고쳐진 것 / 새로 틀린 것 (두 실행 모두 평가된 %d장)%n%n", ts.size()));
            md.append(String.format("- 고쳐짐 %d장, 새로 틀림 %d장, 순변화 %+d장 (계속 맞음 %d, 계속 틀림 %d)%n",
                    count(ts, Change.FIXED), count(ts, Change.REGRESSED),
                    count(ts, Change.FIXED) - count(ts, Change.REGRESSED),
                    count(ts, Change.STILL_RIGHT), count(ts, Change.STILL_WRONG)));
            appendTypes(md, "고쳐짐 유형 (정답: 이전 예측 → 새 예측)", typeCounts(ts, Change.FIXED));
            appendTypes(md, "새로 틀림 유형 (정답: 이전 예측 → 새 예측)", typeCounts(ts, Change.REGRESSED));
        }
        md.append("\n> 표본별 목록(파일명 포함)은 `compare.local.*.md`에 있으며 커밋되지 않는다.\n");
        return md.toString();
    }

    /** 파일명이 들어 있어 커밋하지 않는 상세 목록. */
    static String renderLocal(PromptVersion baseVersion, PromptVersion nextVersion, Map<String, Run[]> runs) {
        StringBuilder md = new StringBuilder("# 고쳐진 것 / 새로 틀린 것 목록 (개인 데이터, 커밋 금지)\n");
        for (Map.Entry<String, Run[]> e : runs.entrySet()) {
            List<Transition> ts = transitions(e.getValue()[0], e.getValue()[1]);
            md.append("\n## ").append(e.getKey()).append(" (").append(baseVersion.label()).append(" → ")
                    .append(nextVersion.label()).append(")\n");
            for (Change change : List.of(Change.FIXED, Change.REGRESSED)) {
                md.append("\n### ").append(change == Change.FIXED ? "고쳐짐" : "새로 틀림").append('\n');
                ts.stream().filter(t -> t.change() == change).forEach(t -> md.append(String.format("- %s (%d자): %s, %s → %s%n",
                        t.base().filename(), t.base().ocrChars(), t.base().expected(), t.base().predicted(), t.next().predicted())));
            }
        }
        return md.toString();
    }

    private static void appendTypes(StringBuilder md, String title, Map<String, Long> types) {
        md.append("\n").append(title).append(":\n");
        if (types.isEmpty()) {
            md.append("- 없음\n");
            return;
        }
        types.forEach((type, count) -> md.append("- ").append(type).append(" ×").append(count).append('\n'));
    }

    private static String score(Score s) {
        return s == null || s.total() == 0 ? "-" : String.format("%.1f%% (%d/%d)", 100 * s.rate(), s.correct(), s.total());
    }

    private static String plain(Score s) {
        return s == null ? "-" : s.correct() + "/" + s.total();
    }

    private static String delta(Score base, Score next) {
        if (base == null || next == null || base.total() == 0 || next.total() == 0) {
            return "-";
        }
        return String.format("%+.1f%%p (%+d장)", 100 * (next.rate() - base.rate()), next.correct() - base.correct());
    }
}
