package com.remine.server.classifier.llm;

import org.springframework.http.HttpHeaders;
import org.springframework.web.client.RestClientResponseException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 호출 실패를 어떻게 다룰지 판단한다. 429·5xx·통신 오류만 재시도하고, 서버가 알려 준 대기 시간
 * (Retry-After 헤더 또는 Google RPC RetryInfo.retryDelay)이 있으면 그것을 따르고 없으면 지수 백오프를 쓴다.
 */
final class RetryAdvice {

    static final Duration BASE_BACKOFF = Duration.ofSeconds(2);
    static final Duration MAX_BACKOFF = Duration.ofSeconds(60);

    private static final Pattern GOOGLE_DURATION = Pattern.compile("^(\\d+(?:\\.\\d+)?)s$");

    private RetryAdvice() {
    }

    /** 429, 5xx, 통신 오류는 재시도한다. 400·401·403·404 같은 나머지 4xx는 다시 해도 같으므로 재시도하지 않는다. */
    static boolean isRetryable(RuntimeException e) {
        if (e instanceof RestClientResponseException response) {
            int status = response.getStatusCode().value();
            return status == 429 || status >= 500;
        }
        return true;
    }

    /** 서버가 알려 준 대기 시간. 없으면 비어 있다. */
    static Optional<Duration> serverSuggestedDelay(RuntimeException e, JsonMapper mapper, Instant now) {
        if (!(e instanceof RestClientResponseException response)) {
            return Optional.empty();
        }
        Optional<Duration> fromHeader = parseRetryAfter(
                response.getResponseHeaders() == null ? null
                        : response.getResponseHeaders().getFirst(HttpHeaders.RETRY_AFTER), now);
        if (fromHeader.isPresent()) {
            return fromHeader;
        }
        return parseRetryInfo(mapper, response.getResponseBodyAsString());
    }

    /** Retry-After: 초 단위 정수 또는 HTTP-date. */
    static Optional<Duration> parseRetryAfter(String value, Instant now) {
        if (value == null || value.isBlank()) {
            return Optional.empty();
        }
        String text = value.trim();
        try {
            return Optional.of(Duration.ofSeconds(Long.parseLong(text)));
        } catch (NumberFormatException notSeconds) {
            try {
                Instant at = ZonedDateTime.parse(text, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant();
                return Optional.of(at.isAfter(now) ? Duration.between(now, at) : Duration.ZERO);
            } catch (RuntimeException notDate) {
                return Optional.empty();
            }
        }
    }

    /** 본문의 error.details[]에서 RetryInfo.retryDelay("34s", "0.5s")를 찾는다. */
    static Optional<Duration> parseRetryInfo(JsonMapper mapper, String body) {
        if (body == null || body.isBlank()) {
            return Optional.empty();
        }
        try {
            for (JsonNode detail : mapper.readTree(body).path("error").path("details")) {
                if (!detail.path("@type").asString("").endsWith("RetryInfo")) {
                    continue;
                }
                Matcher m = GOOGLE_DURATION.matcher(detail.path("retryDelay").asString("").trim());
                if (m.matches()) {
                    return Optional.of(Duration.ofMillis(Math.round(Double.parseDouble(m.group(1)) * 1000)));
                }
            }
        } catch (RuntimeException ignored) {
            // JSON이 아닌 본문이면 서버 제안 없음
        }
        return Optional.empty();
    }

    /** 지수 백오프: 2s, 4s, 8s, 16s … 최대 60s. attempt는 1부터. */
    static Duration backoff(int attempt) {
        long factor = 1L << Math.min(Math.max(attempt - 1, 0), 10);
        Duration wait = BASE_BACKOFF.multipliedBy(factor);
        return wait.compareTo(MAX_BACKOFF) > 0 ? MAX_BACKOFF : wait;
    }

    /** 실패 원인 요약(상태 코드와 본문). errors.local.*.md에 남긴다. */
    static String describe(RuntimeException e) {
        if (e instanceof RestClientResponseException response) {
            return response.getStatusCode().value() + " " + response.getResponseBodyAsString();
        }
        return e.getClass().getSimpleName() + ": " + e.getMessage();
    }
}
