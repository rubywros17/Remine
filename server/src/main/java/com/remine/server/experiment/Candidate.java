package com.remine.server.experiment;

/** candidates.json의 후보 한 줄. 단가는 USD / 1M tokens. */
public record Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok) {

    public double costUsd(double inputTokens, double outputTokens) {
        return (inputTokens * inputPerMTok + outputTokens * outputPerMTok) / 1_000_000.0;
    }
}
