package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.screenshot.Category;
import tools.jackson.databind.json.JsonMapper;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.function.LongConsumer;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

/**
 * 모델 하나에 대한 LLM 분류 호출. 프롬프트·파싱·재시도·호출 간격은 공통이고 {@link LlmProvider}만 다르다.
 * 운영(HybridLlmClassifier)과 실험 러너가 같은 코드를 쓴다. 호출 결과는 {@link LlmOutcome}으로 돌려주며
 * 실패를 조용히 ETC로 바꾸지 않는다(상태로 구분한다).
 * 스레드 안전: 호출 간격 제한({@link CallPacer})이 동기화되어 있어 여러 요청 스레드가 공유해도 된다.
 */
public class LlmClassifier {

    static final int MAX_ATTEMPTS = 5;
    // 서버가 이보다 오래 기다리라고 하면(일일 한도 소진 등) 기다리지 않고 포기한다.
    static final Duration MAX_SERVER_WAIT = Duration.ofSeconds(120);
    private static final Duration SERVER_WAIT_MARGIN = Duration.ofSeconds(1);

    private final String model;
    private final LlmProvider provider;
    private final JsonMapper mapper;
    private final String systemPrompt;
    private final String batchSystemPrompt;
    private final LongConsumer sleepMillis;
    private final CallPacer pacer;
    private final LongSupplier nanoClock;

    public LlmClassifier(String model, long minIntervalMs, LlmProvider provider, JsonMapper mapper,
                         PromptVersion promptVersion) {
        this(model, minIntervalMs, provider, mapper, promptVersion, LlmClassifier::sleep, System::nanoTime);
    }

    // 테스트에서 대기와 시계를 바꿔 끼울 수 있게 한다.
    LlmClassifier(String model, long minIntervalMs, LlmProvider provider, JsonMapper mapper,
                  PromptVersion promptVersion, LongConsumer sleepMillis, LongSupplier nanoClock) {
        this.model = model;
        this.provider = provider;
        this.mapper = mapper;
        this.systemPrompt = LlmPrompt.system(promptVersion);
        this.batchSystemPrompt = LlmPrompt.batchSystem(promptVersion);
        this.sleepMillis = sleepMillis;
        this.nanoClock = nanoClock;
        this.pacer = new CallPacer(minIntervalMs, nanoClock, sleepMillis);
    }

    public String model() {
        return model;
    }

    /**
     * 호출 간격을 지키고, 429·5xx·통신 오류는 최대 {@value #MAX_ATTEMPTS}회까지 재시도한다.
     * 대기는 서버가 알려 준 시간(Retry-After / RetryInfo)을 우선하고 없으면 지수 백오프다.
     * 응답 시간은 성공한 호출만 잰다(간격·재시도 대기 제외).
     */
    public LlmOutcome classifyWithUsage(String ocrText) {
        return classifyWithUsage(ocrText, null);
    }

    /**
     * jpegImage가 null이 아니면 OCR 텍스트와 함께 이미지를 보낸다(text+image).
     * 프롬프트는 동일하고 user 메시지에 "이미지도 참고하라"는 한 줄만 더한다.
     */
    public LlmOutcome classifyWithUsage(String ocrText, byte[] jpegImage) {
        String user = jpegImage == null ? LlmPrompt.user(ocrText) : LlmPrompt.userWithImage(ocrText);
        Call call = callWithRetry(() -> jpegImage == null
                ? provider.call(model, systemPrompt, user)
                : provider.call(model, systemPrompt, user, jpegImage));
        if (call.reply() == null) {
            return call.failure();
        }
        LlmReply reply = call.reply();
        LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper, reply.text());
        return new LlmOutcome(parsed.result(), call.usage(),
                parsed.ok() ? LlmOutcome.Status.OK : LlmOutcome.Status.PARSE_FAILED,
                withNote(reply),
                false,
                parsed.ok() ? "" : "응답 형식 오류" + (reply.note().isEmpty() ? "" : " (" + reply.note() + ")"));
    }

    /** 배치 결과. outcomes는 입력 순서와 같다. calls는 실제 HTTP 호출마다(배치 1번 + 단건 재시도) 캡처 수와 사용량이다. */
    public record BatchOutcome(List<LlmOutcome> outcomes, List<CallUsage> calls) {
    }

    /** 호출 1번이 다룬 캡처 수와 토큰·응답 시간. 실패한 호출은 {@link LlmUsage#NONE}. */
    public record CallUsage(int items, LlmUsage usage) {
    }

    /**
     * 여러 장을 한 요청으로 분류한다({@link LlmPrompt#batchSystem}, 캡처는 순번으로만 식별).
     * <ul>
     *   <li>응답에서 빠졌거나 해석할 수 없는 장 → 그 장만 {@link #classifyWithUsage}로 단건 재시도</li>
     *   <li>응답 전체가 JSON이 아님 → 전원 단건 재시도</li>
     *   <li>호출 자체가 실패(재시도 소진) → 단건 재시도 없이 전원 CALL_FAILED (장애 때 호출이 n배로 늘지 않게)</li>
     * </ul>
     * 한 장이면 배치 프롬프트 없이 단건으로 보낸다(배치 크기 1 = 기존 동작). 성공한 장의 사용량은 배치 사용량을 n등분한 값이다.
     */
    public BatchOutcome classifyBatch(List<LlmPrompt.BatchItem> items) {
        if (items.size() == 1) {
            LlmOutcome single = classifyWithUsage(items.get(0).ocrText(), items.get(0).jpegImage());
            return new BatchOutcome(List.of(single), List.of(new CallUsage(1, single.usage())));
        }
        List<LlmPart> parts = LlmPrompt.batchParts(items);
        Call call = callWithRetry(() -> provider.call(model, batchSystemPrompt, parts));
        List<CallUsage> calls = new ArrayList<>();
        calls.add(new CallUsage(items.size(), call.usage()));
        if (call.reply() == null) {
            LlmOutcome failure = call.failure();
            return new BatchOutcome(Collections.nCopies(items.size(), failure), calls);
        }

        LlmPrompt.BatchParsed parsed = LlmPrompt.parseBatch(mapper, call.reply().text(), items.size());
        LlmUsage share = share(call.usage(), items.size());
        List<LlmOutcome> outcomes = new ArrayList<>();
        for (int i = 0; i < items.size(); i++) {
            ClassificationResult result = parsed.results().get(i);
            if (result != null) {
                outcomes.add(new LlmOutcome(result, share, LlmOutcome.Status.OK, withNote(call.reply())));
                continue;
            }
            LlmOutcome retried = classifyWithUsage(items.get(i).ocrText(), items.get(i).jpegImage());
            calls.add(new CallUsage(1, retried.usage()));
            outcomes.add(retried);
        }
        return new BatchOutcome(outcomes, calls);
    }

    private static LlmUsage share(LlmUsage usage, int n) {
        return new LlmUsage(usage.inputTokens() / n, usage.outputTokens() / n, usage.latencyMs());
    }

    private static String withNote(LlmReply reply) {
        return reply.note().isEmpty() ? reply.text() : "[" + reply.note() + "] " + reply.text();
    }

    /** 재시도 루프의 결과. reply가 null이면 실패이고 {@link #failure()}가 CALL_FAILED 결과를 만든다. */
    private record Call(LlmReply reply, LlmUsage usage, LlmOutcome failure) {
    }

    private Call callWithRetry(Supplier<LlmReply> request) {
        RuntimeException last = null;
        int attempts = 0;
        String stopReason = "";
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            pacer.awaitTurn();
            attempts = attempt;
            // 호출 간격 대기(awaitTurn)와 재시도 대기(sleepMillis)는 이 시각 밖이다. 순수 API 응답 시간만 잰다.
            long start = nanoClock.getAsLong();
            try {
                LlmReply reply = request.get();
                long latencyMs = (nanoClock.getAsLong() - start) / 1_000_000;
                return new Call(reply, new LlmUsage(reply.inputTokens(), reply.outputTokens(), latencyMs), null);
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
        return new Call(null, LlmUsage.NONE, new LlmOutcome(new ClassificationResult(Category.ETC, List.of(), ""),
                LlmUsage.NONE, LlmOutcome.Status.CALL_FAILED, detail, !stopReason.isEmpty(),
                RetryAdvice.safeDescribe(last, mapper) + ", 시도 " + attempts + "회"));
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}
