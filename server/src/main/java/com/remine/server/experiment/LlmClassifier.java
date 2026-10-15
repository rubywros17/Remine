package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.domain.screenshot.Category;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.function.LongConsumer;
import java.util.function.LongSupplier;

/** 후보 하나(제공사 + 모델). 프롬프트와 파싱은 공통이고 {@link LlmProvider}만 다르다. */
public class LlmClassifier implements Classifier {

    static final int MAX_ATTEMPTS = 5;
    // 서버가 이보다 오래 기다리라고 하면(일일 한도 소진 등) 기다리지 않고 포기한다.
    static final Duration MAX_SERVER_WAIT = Duration.ofSeconds(120);
    private static final Duration SERVER_WAIT_MARGIN = Duration.ofSeconds(1);

    private final Candidate candidate;
    private final LlmProvider provider;
    private final JsonMapper mapper;
    private final LongConsumer sleepMillis;
    private final CallPacer pacer;
    private final LongSupplier nanoClock;

    public LlmClassifier(Candidate candidate, LlmProvider provider, JsonMapper mapper) {
        this(candidate, provider, mapper, LlmClassifier::sleep, System::nanoTime);
    }

    // 테스트에서 대기와 시계를 바꿔 끼울 수 있게 한다.
    LlmClassifier(Candidate candidate, LlmProvider provider, JsonMapper mapper,
                  LongConsumer sleepMillis, LongSupplier nanoClock) {
        this.candidate = candidate;
        this.provider = provider;
        this.mapper = mapper;
        this.sleepMillis = sleepMillis;
        this.nanoClock = nanoClock;
        this.pacer = new CallPacer(candidate.minIntervalMs(), nanoClock, sleepMillis);
    }

    public Candidate candidate() {
        return candidate;
    }

    @Override
    public ClassificationResult classify(String ocrText) {
        return classifyWithUsage(ocrText).result();
    }

    /**
     * 호출 간격을 지키고, 429·5xx·통신 오류는 최대 {@value #MAX_ATTEMPTS}회까지 재시도한다.
     * 대기는 서버가 알려 준 시간(Retry-After / RetryInfo)을 우선하고 없으면 지수 백오프다.
     * 응답 시간은 성공한 호출만 잰다(간격·재시도 대기 제외).
     */
    public LlmOutcome classifyWithUsage(String ocrText) {
        String user = LlmPrompt.user(ocrText);
        RuntimeException last = null;
        int attempts = 0;
        String stopReason = "";
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            pacer.awaitTurn();
            attempts = attempt;
            // 호출 간격 대기(awaitTurn)와 재시도 대기(sleepMillis)는 이 시각 밖이다. 순수 API 응답 시간만 잰다.
            long start = nanoClock.getAsLong();
            try {
                LlmReply reply = provider.call(candidate.model(), LlmPrompt.SYSTEM, user);
                long latencyMs = (nanoClock.getAsLong() - start) / 1_000_000;
                LlmUsage usage = new LlmUsage(reply.inputTokens(), reply.outputTokens(), latencyMs);
                LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper, reply.text());
                return new LlmOutcome(parsed.result(), usage,
                        parsed.ok() ? LlmOutcome.Status.OK : LlmOutcome.Status.PARSE_FAILED,
                        reply.note().isEmpty() ? reply.text() : "[" + reply.note() + "] " + reply.text());
            } catch (RuntimeException e) {
                last = e;
                if (!RetryAdvice.isRetryable(e)) {
                    stopReason = "재시도 불가 오류";
                    break;
                }
                if (attempt == MAX_ATTEMPTS) {
                    break;
                }
                Optional<Duration> suggested = RetryAdvice.serverSuggestedDelay(e, mapper, Instant.now());
                if (suggested.isPresent() && suggested.get().compareTo(MAX_SERVER_WAIT) > 0) {
                    stopReason = "서버가 " + suggested.get().toSeconds() + "초 후 재시도를 요구해 포기";
                    break;
                }
                Duration wait = suggested.isPresent()
                        ? suggested.get().plus(SERVER_WAIT_MARGIN)
                        : RetryAdvice.backoff(attempt);
                sleepMillis.accept(wait.toMillis());
            }
        }
        String detail = "시도 " + attempts + "회" + (stopReason.isEmpty() ? "" : ", " + stopReason)
                + " | " + RetryAdvice.describe(last);
        return new LlmOutcome(new ClassificationResult(Category.ETC, List.of(), ""), LlmUsage.NONE,
                LlmOutcome.Status.CALL_FAILED, detail);
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}
