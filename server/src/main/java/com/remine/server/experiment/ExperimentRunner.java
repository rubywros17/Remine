package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.Sample;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * experiment 프로필에서만 동작한다. ocr/*.txt + labels.csv로 후보별 분류를 돌려
 * results.md(집계)와 errors.local.md(오답 상세, gitignore)를 쓰고 종료한다.
 * 실행: ./gradlew bootRun --args="--spring.profiles.active=experiment"
 */
@Component
@Profile("experiment")
class ExperimentRunner implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(ExperimentRunner.class);

    private final Path dir;
    private final JsonMapper mapper = JsonMapper.builder().build();

    ExperimentRunner(@Value("${experiment.dir:../experiment}") String dir) {
        this.dir = Path.of(dir);
    }

    @Override
    public void run(String... args) throws IOException {
        List<Candidate> candidates = loadCandidates();
        List<Labeled> labeled = new ArrayList<>();
        int unlabeled = loadLabels(labeled);
        if (labeled.isEmpty()) {
            log.warn("평가할 표본이 없습니다. ocr.sh를 실행하고 labels.csv의 category를 채우세요. (dir={})",
                    dir.toAbsolutePath());
            return;
        }
        log.info("표본 {}장, 후보 {}개", labeled.size(), candidates.size());

        List<ExperimentStats.Report> reports = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        StringBuilder errors = new StringBuilder("# 오답 상세 (개인 데이터, 커밋 금지)\n");

        for (Candidate candidate : candidates) {
            var provider = LlmProviders.create(candidate.provider(), mapper);
            if (provider.isEmpty()) {
                skipped.add(candidate.name() + " (" + LlmProviders.envName(candidate.provider()) + ")");
                continue;
            }
            LlmClassifier classifier = new LlmClassifier(candidate, provider.get(), mapper);
            List<Sample> samples = new ArrayList<>();
            for (Labeled item : labeled) {
                samples.add(classify(classifier, item));
                if (samples.size() % 10 == 0) {
                    log.info("{}: {}/{}", candidate.name(), samples.size(), labeled.size());
                }
            }
            reports.add(ExperimentStats.summarize(candidate, samples));
            appendErrors(errors, candidate, samples);
        }

        Files.writeString(dir.resolve("results.md"),
                ResultsMarkdown.render(LocalDate.now(), labeled.size(), unlabeled, reports, skipped),
                StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("errors.local.md"), errors.toString(), StandardCharsets.UTF_8);
        log.info("완료: {} (후보 {}개 평가, {}개 건너뜀)", dir.resolve("results.md").toAbsolutePath(),
                reports.size(), skipped.size());
    }

    // 서버와 같은 규칙: 글자가 없으면 LLM을 부르지 않고 ETC.
    private Sample classify(LlmClassifier classifier, Labeled item) {
        if (item.ocrText().isBlank()) {
            return new Sample(item.filename(), item.expected(), Category.ETC,
                    LlmOutcome.Status.OK, false, LlmUsage.NONE);
        }
        LlmOutcome outcome = classifier.classifyWithUsage(item.ocrText());
        return new Sample(item.filename(), item.expected(), outcome.result().category(),
                outcome.status(), true, outcome.usage());
    }

    private void appendErrors(StringBuilder errors, Candidate candidate, List<Sample> samples) {
        errors.append("\n## ").append(candidate.name()).append('\n');
        for (Sample s : samples) {
            if (s.status() == LlmOutcome.Status.CALL_FAILED) {
                errors.append("- ").append(s.filename()).append(": 호출 실패\n");
            } else if (s.expected() != s.predicted()) {
                errors.append("- ").append(s.filename()).append(": ")
                        .append(s.expected()).append(" → ").append(s.predicted())
                        .append(s.status() == LlmOutcome.Status.PARSE_FAILED ? " (파싱 실패)" : "")
                        .append('\n');
            }
        }
    }

    private List<Candidate> loadCandidates() throws IOException {
        JsonNode root = mapper.readTree(Files.readString(dir.resolve("candidates.json"), StandardCharsets.UTF_8));
        List<Candidate> candidates = new ArrayList<>();
        root.path("candidates").forEach(node -> candidates.add(new Candidate(
                node.path("name").asString(), node.path("provider").asString(), node.path("model").asString(),
                node.path("inputPerMTok").asDouble(), node.path("outputPerMTok").asDouble())));
        return candidates;
    }

    /** 정답이 채워지고 OCR 파일이 있는 행만 담는다. 정답이 비어 건너뛴 수를 반환한다. */
    private int loadLabels(List<Labeled> out) throws IOException {
        Path labels = dir.resolve("labels.csv");
        if (!Files.exists(labels)) {
            return 0;
        }
        int unlabeled = 0;
        List<String> lines = Files.readAllLines(labels, StandardCharsets.UTF_8);
        for (String line : lines.stream().skip(1).filter(l -> l.contains(",")).toList()) {
            int comma = line.lastIndexOf(',');
            String filename = line.substring(0, comma).trim();
            String category = line.substring(comma + 1).trim();
            if (category.isEmpty()) {
                unlabeled++;
                continue;
            }
            Path ocr = dir.resolve("ocr").resolve(filename.replaceFirst("\\.[^.]+$", "") + ".txt");
            if (!Files.exists(ocr)) {
                log.warn("OCR 파일 없음, 건너뜀: {}", filename);
                continue;
            }
            try {
                out.add(new Labeled(filename, Category.valueOf(category.toUpperCase()),
                        Files.readString(ocr, StandardCharsets.UTF_8).trim()));
            } catch (IllegalArgumentException e) {
                log.warn("알 수 없는 카테고리 '{}', 건너뜀: {}", category, filename);
            }
        }
        return unlabeled;
    }

    private record Labeled(String filename, Category expected, String ocrText) {
    }
}
