package com.remine.server.experiment;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

class ExperimentRunnerOutputTest {

    // 이 테스트들은 API를 부르지 않으므로 키가 없는 것으로 둔다.
    private static final ExperimentRunner.ProviderFactory NO_KEYS = (candidate, mapper) -> Optional.empty();

    @Test
    void 오답_상세_파일명에_실행_시각이_붙는다() {
        String name = ExperimentRunner.errorsFileName(LocalDateTime.of(2026, 10, 15, 14, 26, 59));

        assertThat(name).isEqualTo("errors.local.20261015-1426.md");
    }

    @Test
    void 파일명이_gitignore_패턴_errors_local_와일드카드에_맞는다() {
        String name = ExperimentRunner.errorsFileName(LocalDateTime.of(2026, 1, 2, 3, 4));

        assertThat(name).startsWith("errors.local").endsWith(".md");
    }

    @Test
    void 평가한_후보가_0개면_결과_파일을_하나도_쓰지_않는다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), "{\"candidates\": []}", StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("labels.csv"), "filename,category,alt\na.jpg,PLACE,\n", StandardCharsets.UTF_8);
        Files.createDirectory(dir.resolve("ocr"));
        Files.writeString(dir.resolve("ocr").resolve("a.txt"), "맛집 카페", StandardCharsets.UTF_8);

        new ExperimentRunner(dir.toString(), 0, "", "", "", NO_KEYS).run();
        new ExperimentRunner(dir.toString(), 1, "", "", "", NO_KEYS).run();

        assertThat(listNames(dir))
                .doesNotContain("results.md", "results.limit.md")
                .noneMatch(name -> name.startsWith("errors.local"));
    }

    @Test
    void 기존_결과_파일은_후보가_0개인_실행에_덮어쓰이지_않는다(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), "{\"candidates\": []}", StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("labels.csv"), "filename,category\na.jpg,PLACE\n", StandardCharsets.UTF_8);
        Files.createDirectory(dir.resolve("ocr"));
        Files.writeString(dir.resolve("ocr").resolve("a.txt"), "맛집", StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("results.md"), "이전 결과", StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("errors.local.20260101-0000.md"), "이전 오답", StandardCharsets.UTF_8);

        new ExperimentRunner(dir.toString(), 0, "", "", "", NO_KEYS).run();

        assertThat(Files.readString(dir.resolve("results.md"), StandardCharsets.UTF_8)).isEqualTo("이전 결과");
        assertThat(Files.readString(dir.resolve("errors.local.20260101-0000.md"), StandardCharsets.UTF_8))
                .isEqualTo("이전 오답");
    }

    @Test
    void 실행이_끝나면_종료_훅을_한_번_부른다_결과가_없어도(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), "{\"candidates\": []}", StandardCharsets.UTF_8);
        ExperimentRunner runner = new ExperimentRunner(dir.toString(), 0, "", "", "", NO_KEYS);
        int[] finished = {0};
        runner.onFinish = () -> finished[0]++;

        runner.run();

        assertThat(finished[0]).isEqualTo(1);
    }

    @Test
    void 실행_중_예외가_나도_종료_훅을_부른다(@TempDir Path dir) {
        // candidates.json이 없어 읽기에서 예외가 난다
        ExperimentRunner runner = new ExperimentRunner(dir.toString(), 0, "", "", "", NO_KEYS);
        int[] finished = {0};
        runner.onFinish = () -> finished[0]++;

        org.assertj.core.api.Assertions.assertThatThrownBy(runner::run).isInstanceOf(IOException.class);
        assertThat(finished[0]).isEqualTo(1);
    }

    private List<String> listNames(Path dir) throws IOException {
        try (Stream<Path> files = Files.list(dir)) {
            return files.map(p -> p.getFileName().toString()).toList();
        }
    }
}
