package com.remine.server.classifier.llm;

import java.util.function.LongConsumer;
import java.util.function.LongSupplier;

/**
 * 후보별 호출 간격 제한. 호출 시작 시각 사이가 minIntervalMs 이상이 되도록 대기한다.
 * 429를 맞고 재시도하기보다 처음부터 속도 제한 아래로 보내기 위한 것이다.
 */
final class CallPacer {

    private final long minIntervalNanos;
    private final LongSupplier nanoClock;
    private final LongConsumer sleepMillis;
    private boolean started;
    private long lastStartNanos;

    CallPacer(long minIntervalMs, LongSupplier nanoClock, LongConsumer sleepMillis) {
        this.minIntervalNanos = Math.max(minIntervalMs, 0) * 1_000_000L;
        this.nanoClock = nanoClock;
        this.sleepMillis = sleepMillis;
    }

    /** 호출 직전에 부른다. 직전 호출 시작으로부터 간격이 모자라면 그만큼 기다린다. */
    void awaitTurn() {
        long now = nanoClock.getAsLong();
        if (minIntervalNanos == 0) {
            return;
        }
        if (!started) {
            started = true;
            lastStartNanos = now;
            return;
        }
        long target = lastStartNanos + minIntervalNanos;
        long waitNanos = target - now;
        if (waitNanos > 0) {
            sleepMillis.accept((waitNanos + 999_999L) / 1_000_000L);
            lastStartNanos = target;
        } else {
            lastStartNanos = now;
        }
    }
}
