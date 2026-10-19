package com.remine.server.classifier.llm;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OcrTextTest {

    @Test
    void 공백과_줄바꿈은_글자_수에서_뺀다() {
        assertThat(OcrText.countChars("가나 다\n라\t마")).isEqualTo(5);
        assertThat(OcrText.countChars("   \n ")).isZero();
    }

    @Test
    void null이면_0() {
        assertThat(OcrText.countChars(null)).isZero();
    }

    @Test
    void 이모지는_UTF16_길이가_아니라_한_글자로_센다() {
        assertThat(OcrText.countChars("👀a")).isEqualTo(2);
    }
}
