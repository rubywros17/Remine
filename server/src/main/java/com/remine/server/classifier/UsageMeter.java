package com.remine.server.classifier;

import com.remine.server.classifier.llm.GeminiPricing;
import com.remine.server.classifier.llm.LlmUsage;
import org.springframework.stereotype.Component;

/**
 * Key Numbers 측정용 누적 카운터(서버 기동 또는 마지막 초기화 이후, 메모리에만).
 * LLM 분류기가 호출마다 토큰을, analyze 서비스가 요청마다 처리 시간을 더한다. 값은 건수·토큰·시간뿐이다.
 * 여러 요청 스레드가 공유해서 메서드를 동기화한다(요청당 몇 번 부르는 정도라 경합은 무시할 만하다).
 */
@Component
public class UsageMeter {

    private long requests;
    private long llmCalls;
    private long llmItems;
    private long inputTokens;
    private long outputTokens;
    private long serverElapsedMs;
    private long firstStartNanos;
    private long lastEndNanos;

    /** LLM 호출 1번. items는 이 호출로 분류한 캡처 수(단건 1). 실패한 호출은 토큰 0으로 들어온다. */
    public synchronized void recordCall(int items, LlmUsage usage) {
        llmCalls++;
        llmItems += items;
        inputTokens += usage.inputTokens();
        outputTokens += usage.outputTokens();
    }

    /** analyze 요청 1번. 첫 요청 시작 ~ 마지막 요청 끝을 wall 시간으로 본다(요청 사이 앱의 OCR·전송 시간 포함). */
    public synchronized void recordRequest(long startNanos, long endNanos) {
        if (requests == 0) {
            firstStartNanos = startNanos;
        }
        requests++;
        serverElapsedMs += (endNanos - startNanos) / 1_000_000;
        lastEndNanos = endNanos;
    }

    public synchronized Snapshot snapshot() {
        double cost = GeminiPricing.costUsd(inputTokens, outputTokens);
        return new Snapshot(requests, llmCalls, llmItems, inputTokens, outputTokens, cost,
                llmItems == 0 ? null : cost / llmItems, serverElapsedMs,
                requests == 0 ? 0 : (lastEndNanos - firstStartNanos) / 1_000_000);
    }

    public synchronized void reset() {
        requests = llmCalls = llmItems = inputTokens = outputTokens = serverElapsedMs = 0;
        firstStartNanos = lastEndNanos = 0;
    }

    /** costPerItemUsd는 LLM으로 분류한 캡처가 없으면 null. 비용은 {@link GeminiPricing} 단가로 계산한다. */
    public record Snapshot(long requests, long llmCalls, long llmItems, long inputTokens, long outputTokens,
                           double costUsd, Double costPerItemUsd, long serverElapsedMs, long wallElapsedMs) {
    }
}
