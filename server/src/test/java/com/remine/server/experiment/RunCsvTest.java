package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmOutcome;
import com.remine.server.classifier.llm.LlmUsage;
import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.Sample;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class RunCsvTest {

    private Sample sample(String filename, Category expected, Category alt, Category predicted,
                          LlmOutcome.Status status, int chars) {
        return new Sample(filename, expected, alt, predicted, status, true, new LlmUsage(10, 5, 50), "원문은 기록하지 않는다", chars);
    }

    @Test
    void 쓰고_다시_읽으면_표본별_결과가_그대로_복원된다(@TempDir Path dir) throws IOException {
        Path file = dir.resolve("runs").resolve("20261016-101500.prompt-v2.cand.csv");
        RunCsv.write(file, List.of(
                sample("a.jpg", Category.PLACE, Category.SCHEDULE, Category.SCHEDULE, LlmOutcome.Status.OK, 120),
                sample("b.jpg", Category.INFO, null, Category.ETC, LlmOutcome.Status.PARSE_FAILED, 0),
                sample("c.jpg", Category.CHAT, null, Category.ETC, LlmOutcome.Status.CALL_FAILED, 33)));

        List<RunCsv.Row> rows = RunCsv.read(file);

        assertThat(rows).containsExactly(
                new RunCsv.Row("a.jpg", Category.PLACE, Category.SCHEDULE, Category.SCHEDULE, LlmOutcome.Status.OK, true, 120),
                new RunCsv.Row("b.jpg", Category.INFO, null, Category.ETC, LlmOutcome.Status.PARSE_FAILED, true, 0),
                new RunCsv.Row("c.jpg", Category.CHAT, null, Category.ETC, LlmOutcome.Status.CALL_FAILED, true, 33));
        assertThat(Files.readString(file)).doesNotContain("원문은 기록하지 않는다");
    }

    @Test
    void 파일명에_쉼표가_있어도_뒤의_고정_칸으로_읽는다(@TempDir Path dir) throws IOException {
        Path file = dir.resolve("x.csv");
        Files.writeString(file, RunCsv.HEADER + "\nweird,name.jpg,SHOPPING,,INFO,OK,true,77\n");

        assertThat(RunCsv.read(file)).containsExactly(
                new RunCsv.Row("weird,name.jpg", Category.SHOPPING, null, Category.INFO, LlmOutcome.Status.OK, true, 77));
    }

    @Test
    void 실행_파일명은_시각_버전_후보를_담고_다시_파싱된다() {
        String name = RunCsv.fileName(LocalDateTime.of(2026, 10, 16, 9, 5, 7), PromptVersion.V2, "gemini-3.5-flash-lite+image");

        assertThat(name).isEqualTo("20261016-090507.prompt-v2.gemini-3.5-flash-lite+image.csv");
        assertThat(RunCsv.parseFileName(name)).contains(
                new RunCsv.FileInfo("20261016-090507", PromptVersion.V2, "gemini-3.5-flash-lite+image"));
        assertThat(RunCsv.parseFileName("results.md")).isEmpty();
        assertThat(RunCsv.parseFileName("20261016-090507.prompt-v9.cand.csv")).isEmpty();
    }

    @Test
    void 같은_버전_후보의_여러_실행_중_가장_최근을_고른다(@TempDir Path dir) throws IOException {
        Path runs = dir.resolve("runs");
        RunCsv.write(runs.resolve("20261016-090000.prompt-v1.cand.csv"),
                List.of(sample("old.jpg", Category.INFO, null, Category.INFO, LlmOutcome.Status.OK, 10)));
        RunCsv.write(runs.resolve("20261016-100000.prompt-v1.cand.csv"),
                List.of(sample("new.jpg", Category.INFO, null, Category.INFO, LlmOutcome.Status.OK, 10)));
        RunCsv.write(runs.resolve("20261016-110000.prompt-v2.cand.csv"),
                List.of(sample("v2.jpg", Category.INFO, null, Category.INFO, LlmOutcome.Status.OK, 10)));

        RunCsv.Run latest = RunCsv.latest(runs, PromptVersion.V1, "cand").orElseThrow();

        assertThat(latest.timestamp()).isEqualTo("20261016-100000");
        assertThat(latest.rows()).extracting(RunCsv.Row::filename).containsExactly("new.jpg");
        assertThat(RunCsv.latest(runs, PromptVersion.V1, "other")).isEmpty();
        assertThat(RunCsv.latest(dir.resolve("none"), PromptVersion.V1, "cand")).isEmpty();
    }
}
