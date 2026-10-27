package com.remine.server.classifier;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

import java.time.Duration;
import java.util.List;

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
        @Valid @DefaultValue Analyze analyze,
        @Valid @DefaultValue Image image,
        @Valid @DefaultValue Tags tags,
        @Valid @DefaultValue Interest interest) {

    public enum ClassifierType { FAKE, GEMINI }

    public record Tags(
            /* 저장하지 않는 태그(화면 문구·카테고리명). 비교는 '#'·공백·대소문자를 무시한다. */
            @DefaultValue List<String> stopwords) {
    }

    /** 관심사 감지·주간 집계 기준. 앱에는 minCount를 GET /api/config로 알린다. */
    public record Interest(
            /* 최근 며칠 안의 캡처(taken_at)를 볼지. */
            @Min(1) @DefaultValue("14") int windowDays,
            /* 같은 태그가 이 횟수 이상이면 관심사. */
            @Min(1) @DefaultValue("3") int minCount,
            /* 같은 태그로 알림 후보를 다시 만들지 않는 기간(일). */
            @Min(0) @DefaultValue("28") int alertCooldownDays) {
    }

    public record Llm(
            /* OCR 글자 수(공백 제외)가 이 값 미만이고 이미지가 있으면 이미지도 함께 보낸다. */
            @Min(1) @DefaultValue("150") int imageThresholdChars,
            @Valid @DefaultValue Gemini gemini,
            @Valid @DefaultValue Batch batch) {
    }

    /** LLM 요청 하나에 묶을 캡처 수. 1이면 장당 1요청(배치 끔). 텍스트만/이미지 포함은 따로 묶는다. */
    public record Batch(
            @Min(1) @DefaultValue("10") int textSize,
            @Min(1) @DefaultValue("5") int imageSize) {
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

    /** 분석용 이미지 입력 정책. 앱에는 GET /api/config로 알린다(단일 출처). */
    public record Image(
            /* 장당 최대 바이트. 초과하면 그 캡처만 IMAGE_TOO_LARGE. */
            @Min(1) @DefaultValue("1048576") long maxBytes,
            /* 서버가 이 길이(px)보다 긴 이미지는 긴 변 기준으로 줄인다. */
            @Min(1) @DefaultValue("1024") int maxLongSide,
            /* 디코딩 전에 헤더로 확인하는 픽셀 수 상한(압축폭탄 방어). */
            @Min(1) @DefaultValue("25000000") long maxPixels,
            /* 요청 전체 크기 하드 상한(바이트). 초과하면 413. multipart 설정도 이 값을 쓴다. */
            @Min(1) @DefaultValue("12582912") long maxRequestBytes,
            /* multipart 파트 하나의 하드 상한(바이트). 초과하면 413. */
            @Min(1) @DefaultValue("5242880") long maxPartBytes) {
    }

    public record Analyze(
            /* analyze 요청 하나에 담을 수 있는 최대 캡처 수. 초과하면 400. */
            @Min(1) @DefaultValue("20") int maxBatchSize) {
    }
}
