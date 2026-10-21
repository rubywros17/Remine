package com.remine.server.experiment;

import com.remine.server.experiment.RunComparison.Score;
import com.remine.server.experiment.RunCsv.Row;
import com.remine.server.experiment.RunCsv.Run;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 같은 프롬프트·표본을 Tesseract OCR과 ML Kit OCR로 돌린 결과를 비교한다(API 호출 없음).
 * 하이브리드는 OCR 글자 수가 기준값 이상이면 텍스트 실행, 미만이면 이미지 실행의 결과를 쓴다.
 * 글자 수는 각 OCR 엔진 기준이라, 기준값을 가로지르는 장은 엔진에 따라 쓰는 실행이 바뀐다.
 */
final class MlKitRemeasure {

    private MlKitRemeasure() {
    }

    /** 한 엔진의 실행 묶음: 텍스트 후보와 이미지 후보. */
    record Engine(Run text, Run image) {
        Score textOnly() {
            return RunComparison.accuracy(text);
        }

        Score hybrid(int threshold) {
            return RunComparison.hybrid(text, image, threshold);
        }

        /** 이 엔진의 하이브리드가 이 표본에서 고르는 행. 이미지 실행에 없으면 null. */
        Row chosen(Row textRow, int threshold, Map<String, Row> imageRows) {
            return textRow.ocrChars() >= threshold ? textRow : imageRows.get(textRow.filename());
        }
    }

    /** 기준값을 가로지르는 장. */
    record Flip(String filename, int tesseractChars, int mlkitChars, Row tesseract, Row mlkit) {
    }

    static List<Flip> flips(Engine tess, Engine mlkit, int threshold) {
        Map<String, Row> tessImage = byName(tess.image());
        Map<String, Row> mlImage = byName(mlkit.image());
        Map<String, Row> mlText = byName(mlkit.text());
        return tess.text().rows().stream()
                .filter(t -> mlText.containsKey(t.filename())
                        && (t.ocrChars() >= threshold) != (mlText.get(t.filename()).ocrChars() >= threshold))
                .map(t -> {
                    Row m = mlText.get(t.filename());
                    return new Flip(t.filename(), t.ocrChars(), m.ocrChars(),
                            tess.chosen(t, threshold, tessImage), mlkit.chosen(m, threshold, mlImage));
                })
                .toList();
    }

    /** 커밋해도 되는 집계(파일명 없음). */
    static String renderSummary(Engine tess, Engine mlkit, int threshold, List<Flip> flips) {
        long tessRight = flips.stream().filter(f -> ok(f.tesseract())).count();
        long mlRight = flips.stream().filter(f -> ok(f.mlkit())).count();
        return "# ML Kit 재측정 (프롬프트 v1)\n\n"
                + "| 입력 | Tesseract | ML Kit | 변화 |\n|---|---|---|---|\n"
                + row("텍스트만", tess.textOnly(), mlkit.textOnly())
                + row("하이브리드 " + threshold + "자", tess.hybrid(threshold), mlkit.hybrid(threshold))
                + String.format("%n- %d자 기준이 바뀐 장: %d장 → 하이브리드 정답 Tesseract %d장 / ML Kit %d장%n",
                threshold, flips.size(), tessRight, mlRight)
                + "\n> 표본별 목록(파일명 포함)은 `compare.local.mlkit-remeasure.md`에 있으며 커밋되지 않는다.\n";
    }

    /** 파일명이 들어 있어 커밋하지 않는 상세 목록. */
    static String renderLocal(List<Flip> flips, int threshold) {
        StringBuilder md = new StringBuilder("# " + threshold + "자 기준이 바뀐 장 (개인 데이터, 커밋 금지)\n\n"
                + "| 파일 | 글자 수 T→M | 정답 | Tesseract 하이브리드 | ML Kit 하이브리드 |\n|---|---|---|---|---|\n");
        for (Flip f : flips) {
            md.append(String.format("| %s | %d→%d | %s | %s | %s |%n", f.filename(), f.tesseractChars(), f.mlkitChars(),
                    (f.mlkit() != null ? f.mlkit() : f.tesseract()).expected(), verdict(f.tesseract()), verdict(f.mlkit())));
        }
        return md.toString();
    }

    private static boolean ok(Row r) {
        return r != null && r.evaluated() && r.strictCorrect();
    }

    private static String verdict(Row r) {
        return r == null || !r.evaluated() ? "-" : (r.strictCorrect() ? "O " : "X ") + r.predicted();
    }

    private static Map<String, Row> byName(Run run) {
        Map<String, Row> m = new HashMap<>();
        run.rows().forEach(r -> m.put(r.filename(), r));
        return m;
    }

    private static String row(String label, Score t, Score m) {
        return String.format("| %s | %.1f%% (%d/%d) | %.1f%% (%d/%d) | %+d장 |%n", label,
                100 * t.rate(), t.correct(), t.total(), 100 * m.rate(), m.correct(), m.total(), m.correct() - t.correct());
    }
}
