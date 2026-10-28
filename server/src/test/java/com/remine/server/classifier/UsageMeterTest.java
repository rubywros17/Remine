package com.remine.server.classifier;

import com.remine.server.classifier.llm.LlmUsage;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class UsageMeterTest {

    private static final long MS = 1_000_000L;

    @Test
    void 호출_토큰과_요청_시간을_모아_비용을_계산한다() {
        UsageMeter meter = new UsageMeter();
        meter.recordCall(1, new LlmUsage(1_000_000, 0, 10));  // 입력 1M = $0.30
        meter.recordCall(3, new LlmUsage(0, 1_000_000, 10));  // 출력 1M = $2.50
        meter.recordCall(1, LlmUsage.NONE);                   // 실패한 호출
        meter.recordRequest(100 * MS, 400 * MS);
        meter.recordRequest(1_000 * MS, 1_500 * MS);

        UsageMeter.Snapshot s = meter.snapshot();

        assertThat(s.llmCalls()).isEqualTo(3);
        assertThat(s.llmItems()).isEqualTo(5);
        assertThat(s.costUsd()).isCloseTo(2.80, within(1e-9));
        assertThat(s.costPerItemUsd()).isCloseTo(0.56, within(1e-9));
        assertThat(s.requests()).isEqualTo(2);
        assertThat(s.serverElapsedMs()).isEqualTo(800);   // 300 + 500
        assertThat(s.maxRequestMs()).isEqualTo(500);
        assertThat(s.wallElapsedMs()).isEqualTo(1_400);   // 첫 시작 100 ~ 마지막 끝 1500
    }

    @Test
    void 초기화하면_0이고_장당_비용은_null() {
        UsageMeter meter = new UsageMeter();
        meter.recordCall(1, new LlmUsage(10, 10, 1));
        meter.recordRequest(0, MS);

        meter.reset();

        UsageMeter.Snapshot s = meter.snapshot();
        assertThat(s.llmCalls()).isZero();
        assertThat(s.costUsd()).isZero();
        assertThat(s.costPerItemUsd()).isNull();
        assertThat(s.wallElapsedMs()).isZero();
        assertThat(s.maxRequestMs()).isZero();
    }
}
