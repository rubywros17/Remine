package com.remine.server.classifier.llm;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class CallPacerTest {

    // 대기하면 가짜 시계가 그만큼 흐른다.
    private static final class FakeTime {
        long nanos = 0;
        final List<Long> sleeps = new ArrayList<>();

        void sleep(long millis) {
            sleeps.add(millis);
            nanos += millis * 1_000_000L;
        }
    }

    @Test
    void 첫_호출은_기다리지_않고_다음_호출은_간격을_채운다() {
        FakeTime time = new FakeTime();
        CallPacer pacer = new CallPacer(5000, () -> time.nanos, time::sleep);

        pacer.awaitTurn();
        time.nanos += 1_000_000_000L; // 호출이 1초 걸림
        pacer.awaitTurn();

        assertThat(time.sleeps).containsExactly(4000L);
    }

    @Test
    void 호출이_간격보다_오래_걸렸으면_기다리지_않는다() {
        FakeTime time = new FakeTime();
        CallPacer pacer = new CallPacer(2000, () -> time.nanos, time::sleep);

        pacer.awaitTurn();
        time.nanos += 3_000_000_000L;
        pacer.awaitTurn();

        assertThat(time.sleeps).isEmpty();
    }

    @Test
    void 연속_호출은_매번_간격을_유지한다() {
        FakeTime time = new FakeTime();
        CallPacer pacer = new CallPacer(1000, () -> time.nanos, time::sleep);

        pacer.awaitTurn();
        pacer.awaitTurn();
        pacer.awaitTurn();

        assertThat(time.sleeps).containsExactly(1000L, 1000L);
        assertThat(time.nanos).isEqualTo(2_000_000_000L);
    }

    @Test
    void 간격이_0이면_대기하지_않는다() {
        FakeTime time = new FakeTime();
        CallPacer pacer = new CallPacer(0, () -> time.nanos, time::sleep);

        pacer.awaitTurn();
        pacer.awaitTurn();

        assertThat(time.sleeps).isEmpty();
    }

    @Test
    void 여러_스레드가_동시에_불러도_호출_간격을_지킨다() throws InterruptedException {
        FakeTime time = new FakeTime();
        CallPacer pacer = new CallPacer(1000, () -> time.nanos, time::sleep);
        int threads = 8;
        java.util.concurrent.CountDownLatch start = new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.CountDownLatch done = new java.util.concurrent.CountDownLatch(threads);
        for (int i = 0; i < threads; i++) {
            new Thread(() -> {
                try {
                    start.await();
                    pacer.awaitTurn();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    done.countDown();
                }
            }).start();
        }
        start.countDown();
        done.await();

        // 첫 호출은 대기 없음, 나머지 7번은 각각 정확히 1초씩 기다린다 (동기화가 없으면 중복·누락이 생긴다)
        assertThat(time.sleeps).hasSize(threads - 1).containsOnly(1000L);
        assertThat(time.nanos).isEqualTo((threads - 1) * 1_000_000_000L);
    }
}
