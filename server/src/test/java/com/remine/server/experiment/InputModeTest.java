package com.remine.server.experiment;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class InputModeTest {

    @Test
    void 생략하거나_비우면_text() {
        assertThat(InputMode.parse(null)).isEqualTo(InputMode.TEXT);
        assertThat(InputMode.parse("")).isEqualTo(InputMode.TEXT);
        assertThat(InputMode.parse("text")).isEqualTo(InputMode.TEXT);
    }

    @Test
    void text_image를_읽는다() {
        assertThat(InputMode.parse("text+image")).isEqualTo(InputMode.TEXT_IMAGE);
        assertThat(InputMode.parse(" TEXT+IMAGE ")).isEqualTo(InputMode.TEXT_IMAGE);
    }

    @Test
    void 모르는_값은_예외() {
        assertThatThrownBy(() -> InputMode.parse("image")).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void 후보의_이미지_사용_여부() {
        assertThat(new Candidate("a", "gemini", "m", 1, 1).usesImage()).isFalse();
        assertThat(new Candidate("a+image", "gemini", "m", 1, 1, 1.0, 0, InputMode.TEXT_IMAGE).usesImage()).isTrue();
    }

    @Test
    void 이미지_입력의_비용은_이미지_토큰을_포함한_입력_토큰으로_계산한다() {
        Candidate lite = new Candidate("a+image", "gemini", "m", 0.30, 2.50, 1.0, 0, InputMode.TEXT_IMAGE);

        // 텍스트 456 + 이미지 약 2,000 토큰 = 입력 2,456, 출력 41
        assertThat(lite.costUsd(2456, 41)).isEqualTo((2456 * 0.30 + 41 * 2.50) / 1_000_000.0);
    }
}
