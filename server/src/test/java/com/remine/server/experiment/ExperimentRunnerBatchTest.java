package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmPart;
import com.remine.server.classifier.llm.LlmProvider;
import com.remine.server.classifier.llm.LlmReply;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/** --experiment.batch: 하이브리드 배치로 분류해 compare.local.batch-*.md에만 쓴다. 실제 API 없음(가짜 제공사). */
class ExperimentRunnerBatchTest {

    private static final String CANDIDATES = """
            {"candidates": [{"name": "lite", "provider": "gemini", "model": "m", "input": "text",
              "inputPerMTok": 0.3, "outputPerMTok": 2.5}]}""";

    @Test
    void 텍스트_표본을_묶어_한_번에_부르고_결과는_커밋_안_되는_파일에만_쓴다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), CANDIDATES, StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("labels.csv"), "filename,category,alt\na.jpg,PLACE,\nb.jpg,INFO,\nc.jpg,PLACE,\n",
                StandardCharsets.UTF_8);
        Files.createDirectory(dir.resolve("ocr"));
        for (String stem : List.of("a", "b", "c")) {
            Files.writeString(dir.resolve("ocr").resolve(stem + ".txt"), "카페 영업시간 ".repeat(30), StandardCharsets.UTF_8);
        }
        List<Integer> batchSizes = new ArrayList<>();
        LlmProvider provider = new LlmProvider() {
            @Override
            public LlmReply call(String model, String systemPrompt, String userText) {
                return new LlmReply("{\"category\":\"PLACE\",\"tags\":[],\"summary\":\"\"}", 10, 1);
            }

            @Override
            public LlmReply call(String model, String systemPrompt, List<LlmPart> parts) {
                batchSizes.add(parts.size());
                StringBuilder results = new StringBuilder();
                for (int id = 1; id <= parts.size(); id++) {
                    results.append(id > 1 ? "," : "")
                            .append("{\"id\":\"").append(id).append("\",\"category\":\"PLACE\",\"tags\":[],\"summary\":\"\"}");
                }
                return new LlmReply("{\"results\":[" + results + "]}", 300, 30);
            }
        };
        ExperimentRunner runner = new ExperimentRunner(dir.toString(), 0, "", "", "",
                (candidate, mapper) -> Optional.of(provider));
        runner.batchOption = "2,5";

        runner.run();

        assertThat(batchSizes).containsExactly(2); // 2장 배치 + 남은 1장은 단건
        List<String> names = listNames(dir);
        assertThat(names).anyMatch(n -> n.startsWith("compare.local.batch-v1-2-5."))
                .noneMatch(n -> n.startsWith("results"))
                .doesNotContain("runs");
        String report = Files.readString(dir.resolve(names.stream()
                .filter(n -> n.startsWith("compare.local.batch-")).findFirst().orElseThrow()), StandardCharsets.UTF_8);
        assertThat(report).contains("LLM 호출 2회").contains("66.7% (2/3)");
    }

    private List<String> listNames(Path dir) throws IOException {
        try (Stream<Path> files = Files.list(dir)) {
            return files.map(p -> p.getFileName().toString()).toList();
        }
    }

    @Test
    void 요약_형식_위반을_판정한다() {
        assertThat(ExperimentRunner.summaryViolation("신예은 인스타 스토리 셀카")).isFalse();
        assertThat(ExperimentRunner.summaryViolation("IntentResolver 앱 권한 정보")).isFalse();
        assertThat(ExperimentRunner.summaryViolation("카페 메뉴를 보여 주는 화면")).isTrue();
        assertThat(ExperimentRunner.summaryViolation("니트 가디건 할인 정보입니다")).isTrue();
        assertThat(ExperimentRunner.summaryViolation("니트 가디건 할인 정보.")).isTrue();
        assertThat(ExperimentRunner.summaryViolation("가".repeat(31))).isTrue();
        assertThat(ExperimentRunner.summaryViolation("")).isTrue();
    }
}
