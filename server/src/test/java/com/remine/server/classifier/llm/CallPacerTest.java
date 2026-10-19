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
}
