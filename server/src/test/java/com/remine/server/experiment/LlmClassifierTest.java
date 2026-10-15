package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

class LlmClassifierTest {

    private final JsonMapper mapper = JsonMapper.builder().build();
    private final Candidate candidate = new Candidate("c", "gemini", "m", 1, 1);

    @Test
    void 응답을_분류_결과와_토큰으로_변환한다() {
        LlmProvider provider = (model, system, user) -> new LlmReply(
                "{\"category\":\"ENTERTAINMENT\",\"tags\":[\"드라마\"],\"summary\":\"드라마 정보\"}", 120, 20);

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("드라마 시즌2");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(outcome.result().category()).isEqualTo(Category.ENTERTAINMENT);
        assertThat(outcome.usage().inputTokens()).isEqualTo(120);
        assertThat(outcome.usage().outputTokens()).isEqualTo(20);
    }

    @Test
    void 이해할_수_없는_응답은_PARSE_FAILED() {
        LlmProvider provider = (model, system, user) -> new LlmReply("모르겠어요", 10, 3);

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.PARSE_FAILED);
        assertThat(outcome.result().category()).isEqualTo(Category.ETC);
    }

    private static final String OK_REPLY = "{\"category\":\"CHAT\",\"tags\":[],\"summary\":\"\"}";

    private HttpClientErrorException error(HttpStatus status, String body, HttpHeaders headers) {
        return HttpClientErrorException.create(status, status.getReasonPhrase(), headers,
                body.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
    }

    private LlmClassifier classifier(LlmProvider provider, Candidate c, List<Long> sleeps) {
        return new LlmClassifier(c, provider, mapper, sleeps::add, System::nanoTime);
    }

    @Test
    void 호출이_한_번_실패해도_재시도해서_성공하면_OK() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        LlmProvider provider = (model, system, user) -> {
            if (calls.incrementAndGet() == 1) {
                throw new IllegalStateException("timeout");
            }
            return new LlmReply(OK_REPLY, 5, 5);
        };

        LlmOutcome outcome = classifier(provider, candidate, sleeps).classifyWithUsage("ㅋㅋ");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(calls.get()).isEqualTo(2);
        assertThat(sleeps).containsExactly(2000L);
    }

    @Test
    void 서버가_알려_준_대기_시간을_따른다() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        String body = "{\"error\":{\"details\":[{\"@type\":\"x.RetryInfo\",\"retryDelay\":\"30s\"}]}}";
        LlmProvider provider = (model, system, user) -> {
            if (calls.incrementAndGet() == 1) {
                throw error(HttpStatus.TOO_MANY_REQUESTS, body, new HttpHeaders());
            }
            return new LlmReply(OK_REPLY, 5, 5);
        };

        LlmOutcome outcome = classifier(provider, candidate, sleeps).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(sleeps).containsExactly(31_000L); // 30초 + 여유 1초
    }

    @Test
    void Retry_After_헤더를_따른다() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.RETRY_AFTER, "5");
        LlmProvider provider = (model, system, user) -> {
            if (calls.incrementAndGet() == 1) {
                throw error(HttpStatus.TOO_MANY_REQUESTS, "{}", headers);
            }
            return new LlmReply(OK_REPLY, 5, 5);
        };

        classifier(provider, candidate, sleeps).classifyWithUsage("x");

        assertThat(sleeps).containsExactly(6_000L);
    }

    @Test
    void 서버_제안이_없으면_지수_백오프로_재시도하다_5회_후_실패() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        LlmProvider provider = (model, system, user) -> {
            calls.incrementAndGet();
            throw error(HttpStatus.TOO_MANY_REQUESTS, "{\"error\":{\"message\":\"quota\"}}", new HttpHeaders());
        };

        LlmOutcome outcome = classifier(provider, candidate, sleeps).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.CALL_FAILED);
        assertThat(calls.get()).isEqualTo(LlmClassifier.MAX_ATTEMPTS);
        assertThat(sleeps).containsExactly(2000L, 4000L, 8000L, 16000L);
        assertThat(outcome.raw()).contains("시도 5회").contains("429").contains("quota");
    }

    @Test
    void 서버가_너무_오래_기다리라고_하면_기다리지_않고_포기한다() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.RETRY_AFTER, "3600");
        LlmProvider provider = (model, system, user) -> {
            calls.incrementAndGet();
            throw error(HttpStatus.TOO_MANY_REQUESTS, "{}", headers);
        };

        LlmOutcome outcome = classifier(provider, candidate, sleeps).classifyWithUsage("x");

        assertThat(calls.get()).isEqualTo(1);
        assertThat(sleeps).isEmpty();
        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.CALL_FAILED);
        assertThat(outcome.raw()).contains("3600초");
    }

    @Test
    void 재시도해도_소용없는_4xx는_한_번만_호출한다() {
        AtomicInteger calls = new AtomicInteger();
        List<Long> sleeps = new ArrayList<>();
        LlmProvider provider = (model, system, user) -> {
            calls.incrementAndGet();
            throw error(HttpStatus.BAD_REQUEST, "{\"error\":{\"message\":\"bad field\"}}", new HttpHeaders());
        };

        LlmOutcome outcome = classifier(provider, candidate, sleeps).classifyWithUsage("x");

        assertThat(calls.get()).isEqualTo(1);
        assertThat(sleeps).isEmpty();
        assertThat(outcome.raw()).contains("400").contains("bad field");
    }

    @Test
    void 이미지가_있으면_이미지_호출을_쓰고_user_메시지에_이미지_참고_문구가_붙는다() {
        byte[] jpeg = {1, 2, 3};
        List<String> users = new ArrayList<>();
        List<byte[]> images = new ArrayList<>();
        LlmProvider provider = new LlmProvider() {
            @Override
            public LlmReply call(String model, String system, String user) {
                throw new AssertionError("이미지 호출이어야 한다");
            }

            @Override
            public LlmReply call(String model, String system, String user, byte[] jpegImage) {
                users.add(user);
                images.add(jpegImage);
                return new LlmReply(OK_REPLY, 2400, 20);
            }
        };

        LlmOutcome outcome = new LlmClassifier(candidate, provider, mapper).classifyWithUsage("OCR 텍스트", jpeg);

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(outcome.usage().inputTokens()).isEqualTo(2400);
        assertThat(images).containsExactly(jpeg);
        assertThat(users.get(0)).startsWith(LlmPrompt.user("OCR 텍스트")).contains("이미지");
    }

    @Test
    void 이미지_없는_호출은_기존_프롬프트를_그대로_쓴다() {
        List<String> users = new ArrayList<>();
        LlmProvider provider = (model, system, user) -> {
            users.add(user);
            return new LlmReply(OK_REPLY, 5, 5);
        };

        new LlmClassifier(candidate, provider, mapper).classifyWithUsage("OCR 텍스트");

        assertThat(users).containsExactly(LlmPrompt.user("OCR 텍스트"));
    }

    @Test
    void 응답_시간에는_호출_간격_대기와_재시도_대기가_포함되지_않는다() {
        long[] now = {0};
        AtomicInteger calls = new AtomicInteger();
        Candidate paced = new Candidate("c", "gemini", "m", 1, 1, 1.0, 5000);
        // 두 번째 분류의 첫 시도는 429로 실패(0.2초) → 백오프 대기 → 재시도는 성공(0.8초 소요)
        LlmProvider provider = (model, system, user) -> {
            if (calls.incrementAndGet() == 2) {
                now[0] += 200_000_000L;
                throw error(HttpStatus.TOO_MANY_REQUESTS, "{}", new HttpHeaders());
            }
            now[0] += 800_000_000L;
            return new LlmReply(OK_REPLY, 5, 5);
        };
        LlmClassifier classifier = new LlmClassifier(paced, provider, mapper, ms -> now[0] += ms * 1_000_000L,
                () -> now[0]);

        classifier.classifyWithUsage("앞선 호출로 간격 기준 시각을 만든다");
        LlmOutcome outcome = classifier.classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(outcome.usage().latencyMs()).isEqualTo(800); // 간격 대기·백오프 대기 제외
    }

    @Test
    void 후보의_호출_간격만큼_연속_호출_사이에_기다린다() {
        List<Long> sleeps = new ArrayList<>();
        long[] now = {0};
        Candidate paced = new Candidate("c", "gemini", "m", 1, 1, 1.0, 3000);
        LlmProvider provider = (model, system, user) -> new LlmReply(OK_REPLY, 5, 5);
        LlmClassifier classifier = new LlmClassifier(paced, provider, mapper, ms -> {
            sleeps.add(ms);
            now[0] += ms * 1_000_000L;
        }, () -> now[0]);

        classifier.classifyWithUsage("a");
        classifier.classifyWithUsage("b");
        classifier.classifyWithUsage("c");

        assertThat(sleeps).containsExactly(3000L, 3000L);
    }
}
