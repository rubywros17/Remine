package com.remine.server.experiment;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ExperimentRunnerLimitTest {

    private final List<String> items = List.of("a", "b", "c", "d", "e");

    @Test
    void 제한이_있으면_앞에서부터_N장() {
        assertThat(ExperimentRunner.applyLimit(items, 3)).containsExactly("a", "b", "c");
    }

    @Test
    void 제한이_0이거나_음수면_전체() {
        assertThat(ExperimentRunner.applyLimit(items, 0)).isEqualTo(items);
        assertThat(ExperimentRunner.applyLimit(items, -1)).isEqualTo(items);
    }

    @Test
    void 제한이_표본_수_이상이면_전체() {
        assertThat(ExperimentRunner.applyLimit(items, 5)).isEqualTo(items);
        assertThat(ExperimentRunner.applyLimit(items, 100)).isEqualTo(items);
    }
}
