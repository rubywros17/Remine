package com.remine.server.experiment;

import com.remine.server.classifier.llm.LlmProvider;
import com.remine.server.classifier.llm.LlmReply;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.IntPredicate;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/** 호출이 대부분 실패한 실행은 결과·실행 기록을 쓰지 않고, 재시도 불가 실패가 이어지면 바로 중단한다. */
class ExperimentRunnerIncompleteRunTest {

    private static final String OK_REPLY = "{\"category\":\"INFO\",\"tags\":[],\"summary\":\"\"}";

    private void prepare(Path dir, int samples) throws IOException {
        Files.writeString(dir.resolve("candidates.json"), """
                {"candidates": [{"name": "m", "provider": "gemini", "model": "m",
                                 "inputPerMTok": 1, "outputPerMTok": 1}]}
                """, StandardCharsets.UTF_8);
        StringBuilder labels = new StringBuilder("filename,category,alt\n");
        Files.createDirectory(dir.resolve("ocr"));
        for (int i = 0; i < samples; i++) {
            labels.append("f").append(i).append(".jpg,INFO,\n");
            Files.writeString(dir.resolve("ocr").resolve("f" + i + ".txt"), "내용 " + i, StandardCharsets.UTF_8);
        }
        Files.writeString(dir.resolve("labels.csv"), labels.toString(), StandardCharsets.UTF_8);
    }

    /** failAt이 true인 호출 번호(1부터)에서 400(재시도 불가)을 던지고 나머지는 정상 응답한다. */
    private ExperimentRunner runner(Path dir, AtomicInteger calls, IntPredicate failAt) {
        LlmProvider provider = (model, system, user) -> {
            if (failAt.test(calls.incrementAndGet())) {
                throw HttpClientErrorException.create(HttpStatus.BAD_REQUEST, "Bad Request", new HttpHeaders(),
                        "{\"error\":{\"message\":\"API key not valid.\"}}".getBytes(StandardCharsets.UTF_8),
                        StandardCharsets.UTF_8);
            }
            return new LlmReply(OK_REPLY, 5, 5);
        };
        return new ExperimentRunner(dir.toString(), 0, "", "", "", (candidate, mapper) -> Optional.of(provider));
    }

    private List<String> names(Path dir) throws IOException {
        try (Stream<Path> files = Files.list(dir)) {
            return files.map(p -> p.getFileName().toString()).toList();
        }
    }

    private boolean hasRunFiles(Path dir) throws IOException {
        Path runs = dir.resolve("runs");
        return Files.isDirectory(runs) && !names(runs).isEmpty();
    }

    @Test
    void 불완전_실행_판정은_중단이거나_호출_실패가_10퍼센트를_넘을_때다() {
        assertThat(ExperimentRunner.incompleteReason(39, 39, true)).contains("연속 3건").contains("39/39");
        assertThat(ExperimentRunner.incompleteReason(20, 3, false)).contains("3/20").contains("10% 초과");
        assertThat(ExperimentRunner.incompleteReason(20, 2, false)).isNull(); // 정확히 10%는 허용
        assertThat(ExperimentRunner.incompleteReason(43, 0, false)).isNull();
        assertThat(ExperimentRunner.incompleteReason(0, 0, false)).isNull(); // OCR이 전부 비어 호출이 없었던 경우
    }

    @Test
    void 재시도_불가_실패가_연속_3번이면_그_후보를_중단하고_결과_기록을_쓰지_않는다(@TempDir Path dir) throws IOException {
        prepare(dir, 43);
        AtomicInteger calls = new AtomicInteger();

        runner(dir, calls, call -> true).run();

        assertThat(calls.get()).isEqualTo(ExperimentRunner.MAX_CONSECUTIVE_GIVE_UPS); // 43번이 아니라 3번
        assertThat(names(dir)).noneMatch(n -> n.startsWith("results."));
        assertThat(hasRunFiles(dir)).isFalse();
        // 실패 원인을 볼 수 있도록 오답 상세 파일은 남긴다
        assertThat(names(dir)).anyMatch(n -> n.startsWith("errors.local."));
    }

    @Test
    void 연속이_아니어도_호출_실패가_10퍼센트를_넘으면_불완전한_실행으로_제외한다(@TempDir Path dir) throws IOException {
        prepare(dir, 10);
        AtomicInteger calls = new AtomicInteger();

        runner(dir, calls, call -> call == 2 || call == 5 || call == 8).run(); // 3/10 = 30%, 연속 아님

        assertThat(calls.get()).isEqualTo(10); // 중단되지 않고 끝까지 돈다
        assertThat(names(dir)).noneMatch(n -> n.startsWith("results."));
        assertThat(hasRunFiles(dir)).isFalse();
    }

    @Test
    void 호출_실패가_10퍼센트_이하면_결과와_실행_기록을_쓴다(@TempDir Path dir) throws IOException {
        prepare(dir, 20);
        AtomicInteger calls = new AtomicInteger();

        runner(dir, calls, call -> call == 7).run(); // 1/20 = 5%

        assertThat(names(dir)).contains("results.prompt-v1.md");
        assertThat(hasRunFiles(dir)).isTrue();
        assertThat(Files.readString(dir.resolve("results.prompt-v1.md"), StandardCharsets.UTF_8))
                .contains("| m |").doesNotContain("제외한 후보");
    }
}
