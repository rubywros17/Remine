package com.remine.server.experiment;

/**
 * candidates.json의 후보 한 줄. 단가는 USD / 1M tokens.
 * temperature는 후보별로 지정하며 생략하면 0이다.
 * minIntervalMs는 이 후보의 연속 호출 사이 최소 간격(ms)으로, 속도 제한(429)을 피하는 데 쓴다. 생략하면 0(제한 없음).
 */
public record Candidate(String name, String provider, String model,
                        double inputPerMTok, double outputPerMTok, double temperature, long minIntervalMs) {

    public static final double DEFAULT_TEMPERATURE = 0.0;

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok) {
        this(name, provider, model, inputPerMTok, outputPerMTok, DEFAULT_TEMPERATURE, 0);
    }

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok,
                     double temperature) {
        this(name, provider, model, inputPerMTok, outputPerMTok, temperature, 0);
    }

    public double costUsd(double inputTokens, double outputTokens) {
        return (inputTokens * inputPerMTok + outputTokens * outputPerMTok) / 1_000_000.0;
    }
}
