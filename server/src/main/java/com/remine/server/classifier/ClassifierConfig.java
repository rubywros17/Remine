package com.remine.server.classifier;

import com.remine.server.classifier.llm.GeminiProvider;
import com.remine.server.classifier.llm.HybridLlmClassifier;
import com.remine.server.classifier.llm.LlmClassifier;
import com.remine.server.classifier.llm.PromptVersion;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import tools.jackson.databind.json.JsonMapper;

/**
 * remine.classifier(fake | gemini)에 따라 분류기 빈 하나를 만든다. 기본은 fake다.
 * gemini인데 API 키가 없으면 기동 시 바로 실패한다(첫 요청에서야 알게 되지 않도록).
 * 키는 Spring Environment에서 읽는다: 환경변수 GEMINI_API_KEY(우선) 또는 키 파일(REMINE_ENV_FILE, 기본 ~/.remine.env).
 */
@Configuration
@EnableConfigurationProperties(RemineProperties.class)
public class ClassifierConfig {

    private static final Logger log = LoggerFactory.getLogger(ClassifierConfig.class);

    @Bean
    public Classifier classifier(RemineProperties properties, Environment environment) {
        return switch (properties.classifier()) {
            case FAKE -> {
                log.info("분류기: fake (키워드 기반 임시 구현)");
                yield new FakeClassifier();
            }
            case GEMINI -> geminiClassifier(properties, environment);
        };
    }

    private Classifier geminiClassifier(RemineProperties properties, Environment environment) {
        String key = environment.getProperty(GeminiProvider.API_KEY_PROPERTY);
        if (key == null || key.isBlank()) {
            // 키 값·길이는 어디에도 출력하지 않는다. 기동 실패 화면은 MissingApiKeyFailureAnalyzer가 정리한다.
            throw new MissingApiKeyException(GeminiProvider.API_KEY_PROPERTY);
        }
        RemineProperties.Gemini gemini = properties.llm().gemini();
        JsonMapper mapper = JsonMapper.builder().build();
        GeminiProvider provider = new GeminiProvider(key.trim(), gemini.temperature(), mapper,
                gemini.baseUrl(), gemini.connectTimeout(), gemini.readTimeout());
        // 프롬프트는 v1 고정 (v2는 채택하지 않은 실험 옵션)
        LlmClassifier llm = new LlmClassifier(gemini.model(), gemini.minIntervalMs(), provider, mapper, PromptVersion.V1);
        log.info("분류기: gemini model={} imageThresholdChars={} minIntervalMs={}", gemini.model(),
                properties.llm().imageThresholdChars(), gemini.minIntervalMs());
        return new HybridLlmClassifier(llm, properties.llm().imageThresholdChars());
    }
}
