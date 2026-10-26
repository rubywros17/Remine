package com.remine.server;

import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.FakeClassifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.SystemEnvironmentPropertySource;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 테스트가 개발자 PC의 상태(REMINE_ENV_FILE·~/.remine.env, GEMINI_API_KEY, REMINE_CLASSIFIER)에 영향받지 않고
 * 실제 LLM API에 닿을 수 없다는 것을 고정한다. 설정은 build.gradle의 test 태스크에 있다.
 */
@SpringBootTest
class TestIsolationTest {

    private static final String GOOGLE_HOST = "generativelanguage" + ".googleapis.com";

    @Autowired ConfigurableEnvironment environment;
    @Autowired Classifier classifier;

    @Test
    void 테스트는_사용자_홈의_remine_env를_읽지_않는다() {
        assertThat(environment.getProperty("remine.env-file")).endsWith("no-remine.env");
        // 불러온 외부 설정 파일이 있다면 "Config resource 'file [...]'" 이름의 프로퍼티 소스가 생긴다
        for (PropertySource<?> source : environment.getPropertySources()) {
            assertThat(source.getName()).doesNotContain(".remine.env");
        }
    }

    @Test
    void 키_파일_위치는_환경변수_REMINE_ENV_FILE로도_정할_수_있다() {
        // application.yaml의 ${remine.env-file:...}는 OS 환경변수 REMINE_ENV_FILE로도 채워진다(Spring 이름 변환).
        var env = new SystemEnvironmentPropertySource("env", Map.of("REMINE_ENV_FILE", "E:/secrets/remine.env"));
        assertThat(env.getProperty("remine.env-file")).isEqualTo("E:/secrets/remine.env");
    }

    @Test
    void 테스트의_API_키는_비어_있고_분류기는_fake다() {
        assertThat(environment.getProperty("GEMINI_API_KEY", "")).isBlank();
        assertThat(classifier).isInstanceOf(FakeClassifier.class);
    }

    @Test
    void 테스트_소스에는_실제_API_주소가_없다() throws IOException {
        // 실제 API는 운영 코드(GeminiProvider.DEFAULT_BASE_URL)에만 있다. 테스트는 로컬 가짜 서버나 localhost만 쓴다.
        try (Stream<Path> files = Files.walk(Path.of("src/test/java"))) {
            for (Path file : files.filter(f -> f.toString().endsWith(".java")).toList()) {
                if (file.getFileName().toString().equals("TestIsolationTest.java")) {
                    continue; // 이 가드 자신 (호스트 이름을 쪼개 적어 두었다)
                }
                assertThat(Files.readString(file, StandardCharsets.UTF_8))
                        .as("테스트 소스가 실제 API 주소를 포함: %s", file)
                        .doesNotContain(GOOGLE_HOST);
            }
        }
    }
}
