package com.remine.server.classifier.llm;

/**
 * gemini-3.5-flash-lite 유료 등급 Standard 단가(USD / 1M tokens). 비용 측정(Key Numbers)에만 쓴다.
 * 출처: https://ai.google.dev/gemini-api/docs/pricing (페이지 갱신 2026-10-27, 확인일 2026-10-27).
 * 입력은 text/image 같은 단가(이미지 토큰은 promptTokenCount에 포함), 출력은 사고 토큰 포함.
 * 이 서버의 "배치"는 한 요청에 여러 장을 담는 동기 호출이라 Standard 단가다(비동기 Batch API의 $0.15/$1.25 아님).
 * 모델·가격이 바뀌면 여기와 experiment/candidates.json을 함께 고친다.
 */
public final class GeminiPricing {

    public static final String MODEL = "gemini-3.5-flash-lite";
    public static final double INPUT_USD_PER_MTOK = 0.30;
    public static final double OUTPUT_USD_PER_MTOK = 2.50;

    private GeminiPricing() {
    }

    public static double costUsd(long inputTokens, long outputTokens) {
        return (inputTokens * INPUT_USD_PER_MTOK + outputTokens * OUTPUT_USD_PER_MTOK) / 1_000_000;
    }
}
