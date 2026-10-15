package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class LabelsCsvTest {

    @Test
    void 세_칸_형식은_alt까지_읽는다() {
        LabelsCsv.Row row = LabelsCsv.parseLine("a.jpg,PLACE,SCHEDULE");

        assertThat(row).isEqualTo(new LabelsCsv.Row("a.jpg", "PLACE", "SCHEDULE"));
    }

    @Test
    void 두_칸_형식도_그대로_읽고_alt는_빈_값() {
        LabelsCsv.Row row = LabelsCsv.parseLine("a.jpg,SHOPPING");

        assertThat(row).isEqualTo(new LabelsCsv.Row("a.jpg", "SHOPPING", ""));
    }

    @Test
    void 정답이_비어_있는_템플릿_행() {
        assertThat(LabelsCsv.parseLine("a.jpg,")).isEqualTo(new LabelsCsv.Row("a.jpg", "", ""));
        assertThat(LabelsCsv.parseLine("a.jpg,,")).isEqualTo(new LabelsCsv.Row("a.jpg", "", ""));
    }

    @Test
    void alt만_비어_있는_세_칸_행() {
        assertThat(LabelsCsv.parseLine("a.jpg,INFO,")).isEqualTo(new LabelsCsv.Row("a.jpg", "INFO", ""));
    }

    @Test
    void 공백과_BOM을_정리하고_쉼표_없는_줄은_무시한다() {
        assertThat(LabelsCsv.parseLine("﻿ a.jpg , chat , etc "))
                .isEqualTo(new LabelsCsv.Row("a.jpg", "chat", "etc"));
        assertThat(LabelsCsv.parseLine("")).isNull();
        assertThat(LabelsCsv.parseLine("   ")).isNull();
    }

    @Test
    void 카테고리_값은_대소문자_무관_빈_값은_null_모르는_값은_예외() {
        assertThat(LabelsCsv.parseCategory("place")).isEqualTo(Category.PLACE);
        assertThat(LabelsCsv.parseCategory("  ")).isNull();
        assertThatThrownBy(() -> LabelsCsv.parseCategory("FOOD")).isInstanceOf(IllegalArgumentException.class);
    }
}
