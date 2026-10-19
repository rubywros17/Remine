package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmOutcome;
import com.remine.server.classifier.llm.OcrText;
import com.remine.server.classifier.llm.LlmUsage;
import com.remine.server.domain.screenshot.Category;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 후보 하나의 분류 결과(샘플 목록)를 정확도·속도·비용으로 집계하는 순수 함수 모음. */
public final class ExperimentStats {

    private ExperimentStats() {
    }

    /**
     * called=false는 글자 없는 스크린샷으로 LLM을 부르지 않고 ETC로 처리한 경우.
     * alt는 labels.csv의 허용 정답(없으면 null). 있으면 그 표본은 "애매한 표본"이다.
     * detail은 모델 원문/사유로 errors.local.*.md에만 쓰고 results.md에는 넣지 않는다.
     * ocrChars는 OCR 텍스트의 공백 제외 글자 수. 모르면 -1이고 글자 수 평균에서 빠진다.
     */
    public record Sample(String filename, Category expected, Category alt, Category predicted,
                         LlmOutcome.Status status, boolean called, LlmUsage usage, String detail, int ocrChars) {

        public Sample(String filename, Category expected, Category alt, Category predicted,
                      LlmOutcome.Status status, boolean called, LlmUsage usage, String detail) {
            this(filename, expected, alt, predicted, status, called, usage, detail, -1);
        }

        public Sample(String filename, Category expected, Category predicted,
                      LlmOutcome.Status status, boolean called, LlmUsage usage) {
            this(filename, expected, null, predicted, status, called, usage, "", -1);
        }

        /** 공백(줄바꿈 포함)을 뺀 글자 수. 운영 하이브리드와 같은 계산({@link OcrText#countChars})이다. */
        public static int countChars(String ocrText) {
            return OcrText.countChars(ocrText);
        }

        /** category만 정답으로 인정. */
        boolean strictCorrect() {
            return predicted == expected;
        }

        /** category 또는 alt를 정답으로 인정. */
        boolean lenientCorrect() {
            return strictCorrect() || (alt != null && predicted == alt);
        }

        boolean ambiguous() {
            return alt != null;
        }
    }

    public record CategoryScore(int correct, int total) {
    }

    /** 표본 수와 평균 OCR 글자 수. count가 0이면 평균은 0이고 표시하지 않는다. */
    public record AvgChars(int count, double average) {
    }

    /** OCR 글자 수(공백 제외) 구간. 경계는 50, 150이며 하한 포함·상한 미포함이다. */
    public enum LengthBin {
        SHORT("50자 미만"), MEDIUM("50자 이상 150자 미만"), LONG("150자 이상");

        private final String label;

        LengthBin(String label) {
            this.label = label;
        }

        public String label() {
            return label;
        }

        public static LengthBin of(int chars) {
            return chars < 50 ? SHORT : chars < 150 ? MEDIUM : LONG;
        }
    }

    /** 구간 안의 엄격 정답 수, 허용 정답 수, 표본 수. */
    public record BinScore(int strictCorrect, int lenientCorrect, int total) {
    }

    public record Report(
            Candidate candidate,
            int evaluated,            // CALL_FAILED를 뺀 평가 대상 수
            int correct,              // 엄격: category와 일치
            int lenientCorrect,       // 허용: category 또는 alt와 일치
            int clearEvaluated,       // alt가 없는(명확한) 표본 수
            int clearCorrect,         // 명확한 표본 중 category와 일치
            int ambiguous,            // alt가 있는(애매한) 표본 수
            int parseFailed,
            int callFailed,
            Map<Category, CategoryScore> perCategory,
            long avgLatencyMs,
            long p95LatencyMs,
            double avgInputTokens,
            double avgOutputTokens,
            double costPerImageUsd,
            Map<String, Integer> confusions,
            AvgChars charsCorrect,    // 정답(허용 기준)
            AvgChars charsWrong,      // 오답(허용 기준)
            AvgChars charsEtcWrong,   // 오답 중 ETC로 예측한 것
            Map<LengthBin, BinScore> byLength) {

        /** 엄격 정확도: category만 정답. */
        public double accuracy() {
            return ratio(correct, evaluated);
        }

        /** 허용 정확도: category 또는 alt가 정답. */
        public double lenientAccuracy() {
            return ratio(lenientCorrect, evaluated);
        }

        /** 명확한 표본(alt 없음)만의 정확도. */
        public double clearAccuracy() {
            return ratio(clearCorrect, clearEvaluated);
        }

        private static double ratio(int numerator, int denominator) {
            return denominator == 0 ? 0 : (double) numerator / denominator;
        }
    }

    public static Report summarize(Candidate candidate, List<Sample> samples) {
        int callFailed = 0;
        int parseFailed = 0;
        int correct = 0;
        int lenientCorrect = 0;
        int clearEvaluated = 0;
        int clearCorrect = 0;
        int ambiguous = 0;
        int evaluated = 0;
        Map<Category, int[]> perCategory = new EnumMap<>(Category.class);
        Map<String, Integer> confusions = new LinkedHashMap<>();
        List<Long> latencies = new ArrayList<>();
        long inputTokens = 0;
        long outputTokens = 0;
        // [표본 수, 글자 수 합] — 정답 / 오답 / ETC로 예측한 오답
        long[] charsCorrect = new long[2];
        long[] charsWrong = new long[2];
        long[] charsEtcWrong = new long[2];
        Map<LengthBin, int[]> byLength = new EnumMap<>(LengthBin.class); // [엄격 정답, 허용 정답, 전체]

        for (Sample sample : samples) {
            if (sample.status() == LlmOutcome.Status.CALL_FAILED) {
                callFailed++;
                continue;
            }
            evaluated++;
            if (sample.status() == LlmOutcome.Status.PARSE_FAILED) {
                parseFailed++;
            }
            int[] score = perCategory.computeIfAbsent(sample.expected(), c -> new int[2]);
            score[1]++;
            if (sample.strictCorrect()) {
                correct++;
                score[0]++;
            } else {
                confusions.merge(sample.expected() + "→" + sample.predicted(), 1, Integer::sum);
            }
            if (sample.lenientCorrect()) {
                lenientCorrect++;
            }
            if (sample.ambiguous()) {
                ambiguous++;
            } else {
                clearEvaluated++;
                if (sample.strictCorrect()) {
                    clearCorrect++;
                }
            }
            if (sample.ocrChars() >= 0) {
                int[] bin = byLength.computeIfAbsent(LengthBin.of(sample.ocrChars()), b -> new int[3]);
                bin[2]++;
                if (sample.strictCorrect()) {
                    bin[0]++;
                }
                if (sample.lenientCorrect()) {
                    bin[1]++;
                }
                long[] group = sample.lenientCorrect() ? charsCorrect : charsWrong;
                group[0]++;
                group[1] += sample.ocrChars();
                if (!sample.lenientCorrect() && sample.predicted() == Category.ETC) {
                    charsEtcWrong[0]++;
                    charsEtcWrong[1] += sample.ocrChars();
                }
            }
            if (sample.called()) {
                latencies.add(sample.usage().latencyMs());
                inputTokens += sample.usage().inputTokens();
                outputTokens += sample.usage().outputTokens();
            }
        }

        int calls = latencies.size();
        double avgIn = calls == 0 ? 0 : (double) inputTokens / calls;
        double avgOut = calls == 0 ? 0 : (double) outputTokens / calls;

        Map<Category, CategoryScore> scores = new EnumMap<>(Category.class);
        perCategory.forEach((category, s) -> scores.put(category, new CategoryScore(s[0], s[1])));

        return new Report(candidate, evaluated, correct, lenientCorrect, clearEvaluated, clearCorrect, ambiguous,
                parseFailed, callFailed, scores,
                calls == 0 ? 0 : Math.round(latencies.stream().mapToLong(Long::longValue).average().orElse(0)),
                percentile95(latencies), avgIn, avgOut, candidate.costUsd(avgIn, avgOut), confusions,
                avgChars(charsCorrect), avgChars(charsWrong), avgChars(charsEtcWrong), binScores(byLength));
    }

    private static Map<LengthBin, BinScore> binScores(Map<LengthBin, int[]> raw) {
        Map<LengthBin, BinScore> scores = new EnumMap<>(LengthBin.class);
        raw.forEach((bin, v) -> scores.put(bin, new BinScore(v[0], v[1], v[2])));
        return scores;
    }

    private static AvgChars avgChars(long[] countAndSum) {
        int count = (int) countAndSum[0];
        return new AvgChars(count, count == 0 ? 0 : (double) countAndSum[1] / count);
    }

    // nearest-rank 방식 p95
    static long percentile95(List<Long> values) {
        if (values.isEmpty()) {
            return 0;
        }
        List<Long> sorted = values.stream().sorted(Comparator.naturalOrder()).toList();
        int rank = (int) Math.ceil(0.95 * sorted.size());
        return sorted.get(Math.max(rank, 1) - 1);
    }
}
