package com.remine.server.classifier;

import com.remine.server.classifier.llm.HybridLlmClassifier;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * remine.classifier에 따른 빈 선택과 gemini 키 검증. 네트워크 호출은 없다(빈 생성만).
 * OS 환경변수·시스템 프로퍼티 소스를 제거하므로 개발자 PC의 GEMINI_API_KEY 유무와 무관하게 같은 결과다.
 */
class ClassifierConfigTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withInitializer(context -> {
                context.getEnvironment().getPropertySources().remove("systemEnvironment");
                context.getEnvironment().getPropertySources().remove("systemProperties");
            })
            .withUserConfiguration(ClassifierConfig.class)
            .withBean(UsageMeter.class);

    @Test
    void 설정이_없으면_fake가_기본이다() {
        runner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context.getBean(Classifier.class)).isInstanceOf(FakeClassifier.class);
        });
    }

    @Test
    void fake를_명시해도_키가_필요_없다() {
        runner.withPropertyValues("remine.classifier=fake").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context.getBean(Classifier.class)).isInstanceOf(FakeClassifier.class);
        });
    }

    @Test
    void gemini이고_키가_있으면_하이브리드_분류기를_만들고_설정을_반영한다() {
        runner.withPropertyValues(
                "remine.classifier=gemini",
                "GEMINI_API_KEY=dummy-test-key",
                "remine.llm.gemini.base-url=http://localhost:1",   // 어떤 호출도 로컬 포트 1로만 간다
                "remine.llm.gemini.model=model-from-config",
                "remine.llm.image-threshold-chars=200").run(context -> {
            assertThat(context).hasNotFailed();
            HybridLlmClassifier classifier = (HybridLlmClassifier) context.getBean(Classifier.class);
            assertThat(classifier.imageThresholdChars()).isEqualTo(200);
            assertThat(classifier.model()).isEqualTo("model-from-config");
        });
    }

    @Test
    void 기본_설정값은_실험에서_정한_값이다() {
        runner.withPropertyValues("remine.classifier=gemini", "GEMINI_API_KEY=dummy-test-key",
                "remine.llm.gemini.base-url=http://localhost:1").run(context -> {
            HybridLlmClassifier classifier = (HybridLlmClassifier) context.getBean(Classifier.class);
            RemineProperties properties = context.getBean(RemineProperties.class);
            assertThat(classifier.imageThresholdChars()).isEqualTo(150);
            assertThat(classifier.model()).isEqualTo("gemini-3.5-flash-lite");
            assertThat(properties.llm().gemini().temperature()).isEqualTo(1.0);
            assertThat(properties.llm().gemini().minIntervalMs()).isEqualTo(4500);
            assertThat(properties.analyze().maxBatchSize()).isEqualTo(20);
        });
    }

    @Test
    void gemini인데_키가_없으면_기동이_명확한_메시지로_실패한다() {
        runner.withPropertyValues("remine.classifier=gemini").run(context -> {
            assertThat(context).hasFailed();
            assertThat(rootMessage(context.getStartupFailure()))
                    .contains("remine.classifier=gemini").contains("GEMINI_API_KEY").contains("~/.remine.env");
        });
    }

    @Test
    void gemini인데_키가_비어_있거나_공백이면_실패한다() {
        runner.withPropertyValues("remine.classifier=gemini", "GEMINI_API_KEY=").run(context -> {
            assertThat(context).hasFailed();
            assertThat(rootMessage(context.getStartupFailure())).contains("GEMINI_API_KEY");
        });
        runner.withPropertyValues("remine.classifier=gemini", "GEMINI_API_KEY=   ").run(context ->
                assertThat(context).hasFailed());
    }

    @Test
    void 알_수_없는_분류기_값은_바인딩_오류로_실패한다() {
        runner.withPropertyValues("remine.classifier=gpt").run(context -> {
            assertThat(context).hasFailed();
            assertThat(String.valueOf(context.getStartupFailure())).contains("classifier");
        });
    }

    @Test
    void 잘못된_숫자_설정은_검증에서_실패한다() {
        runner.withPropertyValues("remine.llm.image-threshold-chars=0").run(context ->
                assertThat(context).hasFailed());
        runner.withPropertyValues("remine.analyze.max-batch-size=0").run(context ->
                assertThat(context).hasFailed());
    }

    private static String rootMessage(Throwable failure) {
        Throwable cause = failure;
        while (cause.getCause() != null) {
            cause = cause.getCause();
        }
        return String.valueOf(cause.getMessage());
    }
}
