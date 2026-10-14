package com.remine.server.experiment;

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
     * detail은 모델 원문/사유로 errors.local.md에만 쓰고 results.md에는 넣지 않는다.
     */
    public record Sample(String filename, Category expected, Category predicted,
                         LlmOutcome.Status status, boolean called, LlmUsage usage, String detail) {

        public Sample(String filename, Category expected, Category predicted,
                      LlmOutcome.Status status, boolean called, LlmUsage usage) {
            this(filename, expected, predicted, status, called, usage, "");
        }
    }

    public record CategoryScore(int correct, int total) {
    }

    public record Report(
            Candidate candidate,
            int evaluated,            // CALL_FAILED를 뺀 평가 대상 수
            int correct,
            int parseFailed,
            int callFailed,
            Map<Category, CategoryScore> perCategory,
            long avgLatencyMs,
            long p95LatencyMs,
            double avgInputTokens,
            double avgOutputTokens,
            double costPerImageUsd,
            Map<String, Integer> confusions) {

        public double accuracy() {
            return evaluated == 0 ? 0 : (double) correct / evaluated;
        }
    }

    public static Report summarize(Candidate candidate, List<Sample> samples) {
        int callFailed = 0;
        int parseFailed = 0;
        int correct = 0;
        int evaluated = 0;
        Map<Category, int[]> perCategory = new EnumMap<>(Category.class);
        Map<String, Integer> confusions = new LinkedHashMap<>();
        List<Long> latencies = new ArrayList<>();
        long inputTokens = 0;
        long outputTokens = 0;

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
            if (sample.expected() == sample.predicted()) {
                correct++;
                score[0]++;
            } else {
                confusions.merge(sample.expected() + "→" + sample.predicted(), 1, Integer::sum);
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

        return new Report(candidate, evaluated, correct, parseFailed, callFailed, scores,
                calls == 0 ? 0 : Math.round(latencies.stream().mapToLong(Long::longValue).average().orElse(0)),
                percentile95(latencies), avgIn, avgOut, candidate.costUsd(avgIn, avgOut), confusions);
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
