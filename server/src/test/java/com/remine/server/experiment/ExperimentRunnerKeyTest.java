package com.remine.server.experiment;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mock.env.MockEnvironment;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/** API 키는 스프링 Environment에서 읽고, 없거나 비어 있으면 표본을 읽거나 API를 부르기 전에 끝난다. */
class ExperimentRunnerKeyTest {

    private final JsonMapper mapper = JsonMapper.builder().build();
    private final Candidate candidate = new Candidate("m", "gemini", "m", 1, 1);

    @Test
    void 키는_Environment의_GEMINI_API_KEY에서_읽는다() {
        MockEnvironment environment = new MockEnvironment().withProperty("GEMINI_API_KEY", "test-key-value");

        assertThat(LlmProviders.create(candidate, mapper, environment::getProperty)).isPresent();
    }

    @Test
    void 키가_없거나_비었거나_공백이면_제공사를_만들지_않는다() {
        assertThat(LlmProviders.create(candidate, mapper, new MockEnvironment()::getProperty)).isEmpty();
        assertThat(LlmProviders.create(candidate, mapper,
                new MockEnvironment().withProperty("GEMINI_API_KEY", "")::getProperty)).isEmpty();
        assertThat(LlmProviders.create(candidate, mapper,
                new MockEnvironment().withProperty("GEMINI_API_KEY", "   ")::getProperty)).isEmpty();
    }

    @Test
    void 조회하는_이름은_제공사별_설정_이름이다() {
        AtomicInteger asked = new AtomicInteger();

        LlmProviders.create(candidate, mapper, name -> {
            assertThat(name).isEqualTo("GEMINI_API_KEY");
            asked.incrementAndGet();
            return null;
        });

        assertThat(asked.get()).isEqualTo(1);
    }

    @Test
    void 키가_없으면_표본을_읽거나_호출하기_전에_끝나고_아무_파일도_쓰지_않는다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), """
                {"candidates": [{"name": "m", "provider": "gemini", "model": "m", "inputPerMTok": 1, "outputPerMTok": 1}]}
                """, StandardCharsets.UTF_8);
        // labels.csv·ocr/가 없다: 키 확인이 표본 로딩보다 먼저이므로 "표본 없음" 경로까지 가지 않는다.
        AtomicInteger factoryCalls = new AtomicInteger();

        new ExperimentRunner(dir.toString(), 0, "", "", "", (c, m) -> {
            factoryCalls.incrementAndGet();
            return Optional.empty();
        }).run();

        assertThat(factoryCalls.get()).isEqualTo(1);
        try (Stream<Path> files = Files.list(dir)) {
            assertThat(files.map(p -> p.getFileName().toString()).toList()).containsExactly("candidates.json");
        }
    }

    @Test
    void experiment_프로필은_홈의_remine_env_파일을_선택적으로_불러온다() throws IOException {
        List<PropertySource<?>> sources = new YamlPropertySourceLoader()
                .load("experiment", new ClassPathResource("application-experiment.yaml"));
        Map<?, ?> merged = sources.stream().map(PropertySource::getSource)
                .filter(Map.class::isInstance).map(Map.class::cast).findFirst().orElseThrow();

        // optional: 파일이 없어도 기동하고, [.properties]로 확장자 없는 파일을 properties로 읽는다.
        assertThat(String.valueOf(merged.get("spring.config.import")))
                .isEqualTo("optional:file:${user.home}/.remine.env[.properties]");
    }
}
