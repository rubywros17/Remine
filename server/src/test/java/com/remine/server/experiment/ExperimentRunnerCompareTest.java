package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmOutcome;
import com.remine.server.classifier.llm.LlmUsage;
import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.Sample;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** --experiment.compare 모드: API 호출 없이 저장된 실행끼리 비교해 리포트를 쓴다. */
class ExperimentRunnerCompareTest {

    // 이 테스트들은 API를 부르지 않으므로 키가 없는 것으로 둔다.
    private static final ExperimentRunner.ProviderFactory NO_KEYS = (candidate, mapper) -> Optional.empty();

    private static final String CANDIDATES = """
            {"candidates": [
              {"name": "m", "provider": "gemini", "model": "m", "inputPerMTok": 1, "outputPerMTok": 1},
              {"name": "m+image", "provider": "gemini", "model": "m", "input": "text+image", "inputPerMTok": 1, "outputPerMTok": 1}
            ]}
            """;

    private Sample sample(String file, Category expected, Category predicted, int chars) {
        return new Sample(file, expected, null, predicted, LlmOutcome.Status.OK, true, LlmUsage.NONE, "", chars);
    }

    private void write(Path dir, String ts, PromptVersion version, String candidate, Sample... samples) throws IOException {
        RunCsv.write(dir.resolve("runs").resolve(ts + ".prompt-" + version.label() + "." + candidate + ".csv"),
                List.of(samples));
    }

    @Test
    void 두_버전의_실행이_있으면_요약과_로컬_목록과_하이브리드를_쓴다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), CANDIDATES, StandardCharsets.UTF_8);
        write(dir, "20261016-100000", PromptVersion.V1, "m",
                sample("secret1.jpg", Category.INFO, Category.ETC, 20), sample("secret2.jpg", Category.INFO, Category.INFO, 300));
        write(dir, "20261016-100100", PromptVersion.V1, "m+image",
                sample("secret1.jpg", Category.INFO, Category.SHOPPING, 20), sample("secret2.jpg", Category.INFO, Category.INFO, 300));
        write(dir, "20261016-110000", PromptVersion.V2, "m",
                sample("secret1.jpg", Category.INFO, Category.ETC, 20), sample("secret2.jpg", Category.INFO, Category.INFO, 300));
        write(dir, "20261016-110100", PromptVersion.V2, "m+image",
                sample("secret1.jpg", Category.INFO, Category.INFO, 20), sample("secret2.jpg", Category.INFO, Category.INFO, 300));

        new ExperimentRunner(dir.toString(), 0, "", "", "v1,v2", NO_KEYS).run();

        String summary = Files.readString(dir.resolve("results.compare.prompt-v1-vs-prompt-v2.md"), StandardCharsets.UTF_8);
        String local = Files.readString(dir.resolve("compare.local.prompt-v1-vs-prompt-v2.md"), StandardCharsets.UTF_8);
        assertThat(summary).contains("텍스트만 (m)", "텍스트 + 이미지 (m+image)", "하이브리드 150자 (m)")
                .doesNotContain("secret1", "secret2");
        // v1 하이브리드: 20자는 이미지(SHOPPING, 틀림), 300자는 텍스트(맞음) → 1/2, v2: 이미지(맞음) + 텍스트(맞음) → 2/2
        assertThat(summary).contains("50.0% (1/2)").contains("100.0% (2/2)");
        assertThat(local).contains("secret1.jpg (20자)");
    }

    @Test
    void 한쪽_버전의_실행만_있으면_결과_파일을_쓰지_않는다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), CANDIDATES, StandardCharsets.UTF_8);
        write(dir, "20261016-100000", PromptVersion.V1, "m", sample("a.jpg", Category.INFO, Category.INFO, 20));

        new ExperimentRunner(dir.toString(), 0, "", "", "v1,v2", NO_KEYS).run();

        try (var files = Files.list(dir)) {
            assertThat(files.map(p -> p.getFileName().toString()).toList())
                    .noneMatch(name -> name.startsWith("results.compare") || name.startsWith("compare.local"));
        }
    }

    @Test
    void 잘못된_비교_인자는_파일을_쓰지_않고_끝난다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), CANDIDATES, StandardCharsets.UTF_8);

        new ExperimentRunner(dir.toString(), 0, "", "", "v1", NO_KEYS).run();
        new ExperimentRunner(dir.toString(), 0, "", "", "v1,v9", NO_KEYS).run();

        try (var files = Files.list(dir)) {
            assertThat(files.map(p -> p.getFileName().toString()).toList()).containsExactly("candidates.json");
        }
    }
}
