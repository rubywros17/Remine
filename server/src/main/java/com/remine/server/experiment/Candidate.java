package com.remine.server.experiment;

/**
 * candidates.json의 후보 한 줄. 단가는 USD / 1M tokens.
 * temperature는 분류 결과의 재현성을 위해 기본 0이고, 후보별로 candidates.json에서 바꿀 수 있다.
 */
public record Candidate(String name, String provider, String model,
                        double inputPerMTok, double outputPerMTok, double temperature) {

    public static final double DEFAULT_TEMPERATURE = 0.0;

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok) {
        this(name, provider, model, inputPerMTok, outputPerMTok, DEFAULT_TEMPERATURE);
    }

    public double costUsd(double inputTokens, double outputTokens) {
        return (inputTokens * inputPerMTok + outputTokens * outputPerMTok) / 1_000_000.0;
    }
}
