package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.domain.screenshot.Category;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;

/** 후보 하나(제공사 + 모델). 프롬프트와 파싱은 공통이고 {@link LlmProvider}만 다르다. */
public class LlmClassifier implements Classifier {

    private static final int MAX_ATTEMPTS = 3;

    private final Candidate candidate;
    private final LlmProvider provider;
    private final JsonMapper mapper;

    public LlmClassifier(Candidate candidate, LlmProvider provider, JsonMapper mapper) {
        this.candidate = candidate;
        this.provider = provider;
        this.mapper = mapper;
    }

    public Candidate candidate() {
        return candidate;
    }

    @Override
    public ClassificationResult classify(String ocrText) {
        return classifyWithUsage(ocrText).result();
    }

    /** 429·타임아웃 등은 3회까지 재시도한다. 응답 시간은 성공한 호출만 잰다(재시도 대기 제외). */
    public LlmOutcome classifyWithUsage(String ocrText) {
        String user = LlmPrompt.user(ocrText);
        RuntimeException last = null;
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            long start = System.nanoTime();
            try {
                LlmReply reply = provider.call(candidate.model(), LlmPrompt.SYSTEM, user);
                long latencyMs = (System.nanoTime() - start) / 1_000_000;
                LlmUsage usage = new LlmUsage(reply.inputTokens(), reply.outputTokens(), latencyMs);
                LlmPrompt.Parsed parsed = LlmPrompt.parse(mapper, reply.text());
                return new LlmOutcome(parsed.result(), usage,
                        parsed.ok() ? LlmOutcome.Status.OK : LlmOutcome.Status.PARSE_FAILED, reply.text());
            } catch (RuntimeException e) {
                last = e;
                sleepBeforeRetry(attempt);
            }
        }
        return new LlmOutcome(new ClassificationResult(Category.ETC, List.of(), ""), LlmUsage.NONE,
                LlmOutcome.Status.CALL_FAILED, String.valueOf(last));
    }

    private static void sleepBeforeRetry(int attempt) {
        if (attempt == MAX_ATTEMPTS) {
            return;
        }
        try {
            Thread.sleep(2000L * attempt);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}
