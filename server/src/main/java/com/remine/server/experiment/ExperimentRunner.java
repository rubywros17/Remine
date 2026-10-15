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
    private final int limit;
    private final JsonMapper mapper = JsonMapper.builder().build();

    /** limit: --experiment.limit=N. 0(기본)이면 전체 표본. 형식 검증용 소량 실행에 쓴다. */
    ExperimentRunner(@Value("${experiment.dir:../experiment}") String dir,
                     @Value("${experiment.limit:0}") int limit) {
        this.dir = Path.of(dir);
        this.limit = limit;
    }

    @Override
    public void run(String... args) throws IOException {
        List<Candidate> candidates = loadCandidates();
        List<Labeled> all = new ArrayList<>();
        int unlabeled = loadLabels(all);
        List<Labeled> labeled = applyLimit(all, limit);
        if (labeled.isEmpty()) {
            log.warn("평가할 표본이 없습니다. ocr.sh를 실행하고 labels.csv의 category를 채우세요. (dir={})",
                    dir.toAbsolutePath());
            return;
        }
        boolean limited = limit > 0;
        log.info("표본 {}장{}, 후보 {}개", labeled.size(),
                limited ? " (전체 " + all.size() + "장 중 제한 실행)" : "", candidates.size());

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
                Sample sample = classify(classifier, item);
                samples.add(sample);
                if (limited) {
                    logSample(candidate, sample);
                } else if (samples.size() % 10 == 0) {
                    log.info("{}: {}/{}", candidate.name(), samples.size(), labeled.size());
                }
            }
            reports.add(ExperimentStats.summarize(candidate, samples));
            appendErrors(errors, candidate, samples);
        }

        // 제한 실행은 커밋되는 results.md를 덮어쓰지 않도록 별도 파일(gitignore)에 쓴다.
        Path resultsFile = dir.resolve(limited ? "results.limit.md" : "results.md");
        Files.writeString(resultsFile,
                ResultsMarkdown.render(LocalDate.now(), labeled.size(), unlabeled, reports, skipped),
                StandardCharsets.UTF_8);
        Files.writeString(dir.resolve("errors.local.md"), errors.toString(), StandardCharsets.UTF_8);
        log.info("완료: {} (후보 {}개 평가, {}개 건너뜀)", resultsFile.toAbsolutePath(),
                reports.size(), skipped.size());
    }

    /** 앞에서부터 limit장. 0 이하면 전체, 표본보다 크면 전체. */
    static <T> List<T> applyLimit(List<T> items, int limit) {
        return limit > 0 && limit < items.size() ? items.subList(0, limit) : items;
    }

    // 형식 검증용: 건별 상태·토큰·시간·원문 앞부분을 콘솔에만 출력한다(파일에는 남기지 않음).
    private void logSample(Candidate candidate, Sample s) {
        log.info("[{}] {} → 예측 {} (정답 {}) status={} 토큰 {}/{} {}ms | {}",
                candidate.name(), s.filename(), s.predicted(), s.expected(), s.status(),
                s.usage().inputTokens(), s.usage().outputTokens(), s.usage().latencyMs(), oneLine(s.detail()));
    }

    // 서버와 같은 규칙: 글자가 없으면 LLM을 부르지 않고 ETC.
    private Sample classify(LlmClassifier classifier, Labeled item) {
        if (item.ocrText().isBlank()) {
            return new Sample(item.filename(), item.expected(), item.alt(), Category.ETC,
                    LlmOutcome.Status.OK, false, LlmUsage.NONE, "");
        }
        LlmOutcome outcome = classifier.classifyWithUsage(item.ocrText());
        return new Sample(item.filename(), item.expected(), item.alt(), outcome.result().category(),
                outcome.status(), true, outcome.usage(), outcome.raw());
    }

    private void appendErrors(StringBuilder errors, Candidate candidate, List<Sample> samples) {
        errors.append("\n## ").append(candidate.name()).append('\n');
        for (Sample s : samples) {
            if (s.status() == LlmOutcome.Status.CALL_FAILED) {
                errors.append("- ").append(s.filename()).append(": 호출 실패 ").append(oneLine(s.detail())).append('\n');
            } else if (s.expected() != s.predicted()) {
                errors.append("- ").append(s.filename()).append(": ")
                        .append(s.expected()).append(" → ").append(s.predicted());
                if (s.lenientCorrect()) {
                    errors.append(" (alt ").append(s.alt()).append("와 일치, 허용 정답)");
                }
                if (s.status() == LlmOutcome.Status.PARSE_FAILED) {
                    errors.append(" (파싱 실패) ").append(oneLine(s.detail()));
                }
                errors.append('\n');
            }
        }
    }

    private static String oneLine(String text) {
        String flat = text.replaceAll("\\s+", " ").trim();
        return flat.length() > 200 ? flat.substring(0, 200) + "…" : flat;
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
        for (String line : lines.stream().skip(1).toList()) {
            LabelsCsv.Row row = LabelsCsv.parseLine(line);
            if (row == null) {
                continue;
            }
            if (row.category().isEmpty()) {
                unlabeled++;
                continue;
            }
            Path ocr = dir.resolve("ocr").resolve(row.filename().replaceFirst("\\.[^.]+$", "") + ".txt");
            if (!Files.exists(ocr)) {
                log.warn("OCR 파일 없음, 건너뜀: {}", row.filename());
                continue;
            }
            Category expected;
            try {
                expected = LabelsCsv.parseCategory(row.category());
            } catch (IllegalArgumentException e) {
                log.warn("알 수 없는 카테고리 '{}', 건너뜀: {}", row.category(), row.filename());
                continue;
            }
            out.add(new Labeled(row.filename(), expected, parseAlt(row, expected),
                    Files.readString(ocr, StandardCharsets.UTF_8).trim()));
        }
        return unlabeled;
    }

    // alt가 비었거나 category와 같으면 애매한 표본이 아니다. 알 수 없는 값은 경고 후 무시한다.
    private Category parseAlt(LabelsCsv.Row row, Category expected) {
        try {
            Category alt = LabelsCsv.parseCategory(row.alt());
            return alt == expected ? null : alt;
        } catch (IllegalArgumentException e) {
            log.warn("알 수 없는 alt '{}', 무시함: {}", row.alt(), row.filename());
            return null;
        }
    }

    private record Labeled(String filename, Category expected, Category alt, String ocrText) {
    }
}
