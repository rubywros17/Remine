package com.remine.server.classifier;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

import java.time.Duration;

/**
 * remine.* 설정. 기본값은 실험(experiment/SUMMARY.md)에서 정한 값이다.
 * 잘못된 classifier 값(예: remine.classifier=gpt)은 바인딩 오류로 허용 값 목록과 함께 기동이 실패한다.
 */
@Validated
@ConfigurationProperties("remine")
public record RemineProperties(
        /* 어떤 분류기를 쓸지. 기본 fake, 실제 LLM은 gemini. */
        @DefaultValue("fake") ClassifierType classifier,
        @Valid @DefaultValue Llm llm,
        @Valid @DefaultValue Analyze analyze) {

    public enum ClassifierType { FAKE, GEMINI }

    public record Llm(
            /* OCR 글자 수(공백 제외)가 이 값 미만이고 이미지가 있으면 이미지도 함께 보낸다. */
            @Min(1) @DefaultValue("150") int imageThresholdChars,
            @Valid @DefaultValue Gemini gemini) {
    }

    public record Gemini(
            @NotBlank @DefaultValue("gemini-3.5-flash-lite") String model,
            /* Gemini 3 공식 권장값 1.0 (낮추면 반복·품질 저하 가능). */
            @DefaultValue("1.0") double temperature,
            @NotBlank @DefaultValue("https://generativelanguage.googleapis.com") String baseUrl,
            @DefaultValue("10s") Duration connectTimeout,
            @DefaultValue("60s") Duration readTimeout,
            /* 연속 호출 시작 사이 최소 간격(ms). 4500 = 무료 등급 RPM 15 기준. 유료 등급이면 낮추거나 0. */
            @Min(0) @DefaultValue("4500") long minIntervalMs) {
    }

    public record Analyze(
            /* analyze 요청 하나에 담을 수 있는 최대 캡처 수. 초과하면 400. */
            @Min(1) @DefaultValue("20") int maxBatchSize) {
    }
}
