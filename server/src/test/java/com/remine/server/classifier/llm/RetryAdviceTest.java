package com.remine.server.classifier.llm;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class RetryAdviceTest {

    private static final Instant NOW = Instant.parse("2026-10-15T00:00:00Z");
    private final JsonMapper mapper = JsonMapper.builder().build();

    private HttpClientErrorException client(HttpStatus status, HttpHeaders headers, String body) {
        return HttpClientErrorException.create(status, status.getReasonPhrase(), headers,
                body.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
    }

    @Test
    void 지수_백오프는_2_4_8_16초이고_60초를_넘지_않는다() {
        assertThat(RetryAdvice.backoff(1)).isEqualTo(Duration.ofSeconds(2));
        assertThat(RetryAdvice.backoff(2)).isEqualTo(Duration.ofSeconds(4));
        assertThat(RetryAdvice.backoff(3)).isEqualTo(Duration.ofSeconds(8));
        assertThat(RetryAdvice.backoff(4)).isEqualTo(Duration.ofSeconds(16));
        assertThat(RetryAdvice.backoff(20)).isEqualTo(Duration.ofSeconds(60));
    }

    @Test
    void Retry_After는_초_단위_정수와_HTTP_날짜_모두_읽는다() {
        assertThat(RetryAdvice.parseRetryAfter("30", NOW)).contains(Duration.ofSeconds(30));
        assertThat(RetryAdvice.parseRetryAfter("Thu, 15 Oct 2026 00:00:45 GMT", NOW))
                .contains(Duration.ofSeconds(45));
        assertThat(RetryAdvice.parseRetryAfter("Wed, 14 Oct 2026 00:00:00 GMT", NOW)).contains(Duration.ZERO);
        assertThat(RetryAdvice.parseRetryAfter("곧", NOW)).isEmpty();
        assertThat(RetryAdvice.parseRetryAfter(null, NOW)).isEmpty();
    }

    @Test
    void 본문의_RetryInfo_retryDelay를_읽는다() {
        String body = """
                {"error":{"code":429,"message":"quota","details":[
                  {"@type":"type.googleapis.com/google.rpc.QuotaFailure"},
                  {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"34s"}]}}
                """;

        assertThat(RetryAdvice.parseRetryInfo(mapper, body)).contains(Duration.ofSeconds(34));
        assertThat(RetryAdvice.parseRetryInfo(mapper, "{\"error\":{\"details\":[{\"@type\":\"x.RetryInfo\","
                + "\"retryDelay\":\"0.5s\"}]}}")).contains(Duration.ofMillis(500));
        assertThat(RetryAdvice.parseRetryInfo(mapper, "not json")).isEmpty();
    }

    @Test
    void 헤더가_본문보다_우선한다() {
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.RETRY_AFTER, "7");
        String body = "{\"error\":{\"details\":[{\"@type\":\"x.RetryInfo\",\"retryDelay\":\"34s\"}]}}";

        assertThat(RetryAdvice.serverSuggestedDelay(client(HttpStatus.TOO_MANY_REQUESTS, headers, body), mapper, NOW))
                .contains(Duration.ofSeconds(7));
    }

    @Test
    void 재시도_대상은_429_5xx_통신오류이고_나머지_4xx는_아니다() {
        assertThat(RetryAdvice.isRetryable(client(HttpStatus.TOO_MANY_REQUESTS, new HttpHeaders(), ""))).isTrue();
        assertThat(RetryAdvice.isRetryable(HttpServerErrorException.create(HttpStatus.SERVICE_UNAVAILABLE, "x",
                new HttpHeaders(), new byte[0], StandardCharsets.UTF_8))).isTrue();
        assertThat(RetryAdvice.isRetryable(new IllegalStateException("timeout"))).isTrue();
        assertThat(RetryAdvice.isRetryable(client(HttpStatus.BAD_REQUEST, new HttpHeaders(), ""))).isFalse();
        assertThat(RetryAdvice.isRetryable(client(HttpStatus.UNAUTHORIZED, new HttpHeaders(), ""))).isFalse();
    }
}
