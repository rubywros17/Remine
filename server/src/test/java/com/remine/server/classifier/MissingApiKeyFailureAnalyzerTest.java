package com.remine.server.classifier;

import org.junit.jupiter.api.Test;
import org.springframework.boot.diagnostics.FailureAnalysis;
import org.springframework.core.io.support.SpringFactoriesLoader;
import org.springframework.boot.diagnostics.FailureAnalyzer;

import static org.assertj.core.api.Assertions.assertThat;

class MissingApiKeyFailureAnalyzerTest {

    @Test
    void 기동_실패_안내에_문제와_해결_방법이_있고_키_값은_없다() {
        MissingApiKeyException exception = new MissingApiKeyException("GEMINI_API_KEY");

        FailureAnalysis analysis = new MissingApiKeyFailureAnalyzer().analyze(
                new IllegalStateException("빈 생성 실패", exception));

        assertThat(analysis).isNotNull();
        assertThat(analysis.getDescription()).contains("remine.classifier=gemini").contains("GEMINI_API_KEY");
        assertThat(analysis.getAction()).contains("~/.remine.env").contains("remine.classifier=fake");
    }

    @Test
    void 다른_예외에는_반응하지_않는다() {
        assertThat(new MissingApiKeyFailureAnalyzer().analyze(new IllegalStateException("다른 문제"))).isNull();
    }

    @Test
    void spring_factories에_분석기가_등록되어_있다() {
        // 분석기들은 생성자 인자가 필요해 인스턴스를 만들지 않고 등록된 이름만 확인한다.
        var names = SpringFactoriesLoader.loadFactoryNames(FailureAnalyzer.class, getClass().getClassLoader());

        assertThat(names).contains(MissingApiKeyFailureAnalyzer.class.getName());
    }
}
