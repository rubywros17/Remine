package com.remine.server.experiment;

/**
 * candidates.json의 후보 한 줄. 단가는 USD / 1M tokens.
 * temperature는 후보별로 지정하며 생략하면 0이다.
 * minIntervalMs는 이 후보의 연속 호출 사이 최소 간격(ms)으로, 속도 제한(429)을 피하는 데 쓴다. 생략하면 0(제한 없음).
 * input은 text(OCR 텍스트만) 또는 text+image(OCR 텍스트 + 긴 변 1024px로 줄인 스크린샷)이며 생략하면 text다.
 */
public record Candidate(String name, String provider, String model,
                        double inputPerMTok, double outputPerMTok, double temperature, long minIntervalMs,
                        InputMode input) {

    public static final double DEFAULT_TEMPERATURE = 0.0;

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok) {
        this(name, provider, model, inputPerMTok, outputPerMTok, DEFAULT_TEMPERATURE, 0, InputMode.TEXT);
    }

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok,
                     double temperature) {
        this(name, provider, model, inputPerMTok, outputPerMTok, temperature, 0, InputMode.TEXT);
    }

    public Candidate(String name, String provider, String model, double inputPerMTok, double outputPerMTok,
                     double temperature, long minIntervalMs) {
        this(name, provider, model, inputPerMTok, outputPerMTok, temperature, minIntervalMs, InputMode.TEXT);
    }

    public boolean usesImage() {
        return input == InputMode.TEXT_IMAGE;
    }

    /** 입력 토큰에는 이미지 토큰도 포함되어 있으므로(API의 promptTokenCount) 같은 입력 단가로 계산한다. */
    public double costUsd(double inputTokens, double outputTokens) {
        return (inputTokens * inputPerMTok + outputTokens * outputPerMTok) / 1_000_000.0;
    }
}
