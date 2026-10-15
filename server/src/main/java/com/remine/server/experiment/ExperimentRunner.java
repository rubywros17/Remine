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
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * experiment 프로필에서만 동작한다. ocr/*.txt + labels.csv로 후보별 분류를 돌려
 * results.md(집계)와 errors.local.{실행시각}.md(오답 상세, gitignore)를 쓰고 종료한다.
 * 평가한 후보가 0개면 어떤 파일도 쓰지 않는다.
 * 실행: ./gradlew bootRun --args="--spring.profiles.active=experiment"
 */
@Component
@Profile("experiment")
class ExperimentRunner implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(ExperimentRunner.class);

    private final Path dir;
    private final int limit;
    private final String candidatesFilter;
    private final JsonMapper mapper = JsonMapper.builder().build();

    /**
     * limit: --experiment.limit=N. 0(기본)이면 전체 표본. 형식 검증용 소량 실행에 쓴다.
     * candidatesFilter: --experiment.candidates=모델ID[,모델ID]. 비어 있으면 candidates.json의 전체 후보.
     */
    ExperimentRunner(@Value("${experiment.dir:../experiment}") String dir,
                     @Value("${experiment.limit:0}") int limit,
                     @Value("${experiment.candidates:}") String candidatesFilter) {
        this.dir = Path.of(dir);
        this.limit = limit;
        this.candidatesFilter = candidatesFilter;
    }

    @Override
    public void run(String... args) throws IOException {
        List<Candidate> available = loadCandidates();
        List<Candidate> candidates;
        try {
            candidates = filterCandidates(available, candidatesFilter);
        } catch (IllegalArgumentException e) {
            log.error(e.getMessage());
            return;
        }
        boolean filtered = candidates.size() < available.size();
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
        boolean attempted = false;

        for (Candidate candidate : candidates) {
            var provider = LlmProviders.create(candidate, mapper);
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
            attempted = true;
            ExperimentStats.Report report = ExperimentStats.summarize(candidate, samples);
            appendErrors(errors, candidate, samples);
            if (report.evaluated() == 0) {
                // 호출이 전부 실패해 평가된 표본이 없다. 빈 표가 결과 파일에 들어가지 않게 제외한다.
                skipped.add(candidate.name() + " (호출 " + report.callFailed() + "건 전부 실패)");
                continue;
            }
            reports.add(report);
        }

        // 평가한 후보가 하나도 없으면(키 없음, 호출 전부 실패 등) 결과 파일을 쓰지 않아 이전 결과를 지키지 않는다.
        // 호출을 시도했다면 실패 원인을 볼 수 있도록 시각이 붙은 오답 상세 파일만 남긴다.
        if (reports.isEmpty()) {
            log.warn("평가한 후보가 0개라 결과 파일을 쓰지 않았습니다. 건너뛴 후보: {}", skipped);
            if (attempted) {
                Path errorsFile = uniqueErrorsFile(LocalDateTime.now());
                Files.writeString(errorsFile, errors.toString(), StandardCharsets.UTF_8);
                log.warn("호출 실패 원인은 {} 에서 확인하세요.", errorsFile.getFileName());
            }
            return;
        }

        // 제한·후보 지정 실행은 커밋되는 results.md를 덮어쓰지 않도록 별도 파일에 쓴다.
        Path resultsFile = dir.resolve(resultsFileName(limited, filtered, reports));
        Files.writeString(resultsFile,
                ResultsMarkdown.render(LocalDate.now(), labeled.size(), unlabeled, reports, skipped),
                StandardCharsets.UTF_8);
        Path errorsFile = uniqueErrorsFile(LocalDateTime.now());
        Files.writeString(errorsFile, errors.toString(), StandardCharsets.UTF_8);
        log.info("완료: {} (후보 {}개 평가, {}개 건너뜀), 오답 상세: {}", resultsFile.toAbsolutePath(),
                reports.size(), skipped.size(), errorsFile.getFileName());
    }

    /**
     * 결과 파일명. 전체 실행은 results.md, 표본 제한 실행은 results.limit.md(gitignore),
     * 후보 지정 실행은 results.{후보}.md라서 다른 후보의 기존 결과(results.md)를 지우지 않는다.
     */
    static String resultsFileName(boolean limited, boolean filtered, List<ExperimentStats.Report> reports) {
        if (limited) {
            return "results.limit.md";
        }
        if (filtered) {
            return "results." + reports.stream().map(r -> r.candidate().name()).collect(Collectors.joining("+")) + ".md";
        }
        return "results.md";
    }

    /** filter는 쉼표로 구분한 모델 ID(또는 후보 이름). 비어 있으면 전체. 모르는 ID가 있으면 예외. */
    static List<Candidate> filterCandidates(List<Candidate> available, String filter) {
        if (filter == null || filter.isBlank()) {
            return available;
        }
        List<Candidate> selected = new ArrayList<>();
        List<String> unknown = new ArrayList<>();
        for (String id : filter.split(",")) {
            String wanted = id.trim();
            if (wanted.isEmpty()) {
                continue;
            }
            available.stream()
                    .filter(c -> c.model().equalsIgnoreCase(wanted) || c.name().equalsIgnoreCase(wanted))
                    .findFirst()
                    .ifPresentOrElse(c -> {
                        if (!selected.contains(c)) {
                            selected.add(c);
                        }
                    }, () -> unknown.add(wanted));
        }
        if (!unknown.isEmpty() || selected.isEmpty()) {
            throw new IllegalArgumentException("알 수 없는 후보: " + unknown + " / 사용 가능: "
                    + available.stream().map(Candidate::model).toList());
        }
        return selected;
    }

    /** 실행 시각을 붙인 오답 상세 파일명. 예: errors.local.20261015-1426.md (gitignore 패턴 errors.local*.md) */
    static String errorsFileName(LocalDateTime now) {
        return "errors.local." + now.format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmm")) + ".md";
    }

    // 같은 분에 두 번 실행해도 덮어쓰지 않도록, 이미 있으면 초 단위까지 붙인다.
    private Path uniqueErrorsFile(LocalDateTime now) {
        Path file = dir.resolve(errorsFileName(now));
        if (!Files.exists(file)) {
            return file;
        }
        return dir.resolve("errors.local." + now.format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")) + ".md");
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
                // 원인 파악을 위해 호출 실패 사유는 더 길게 남긴다(상태 코드, 한도 메시지, 재시도 정보).
                errors.append("- ").append(s.filename()).append(": 호출 실패 ")
                        .append(oneLine(s.detail(), 1500)).append('\n');
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
        return oneLine(text, 200);
    }

    private static String oneLine(String text, int max) {
        String flat = text.replaceAll("\\s+", " ").trim();
        return flat.length() > max ? flat.substring(0, max) + "…" : flat;
    }

    private List<Candidate> loadCandidates() throws IOException {
        JsonNode root = mapper.readTree(Files.readString(dir.resolve("candidates.json"), StandardCharsets.UTF_8));
        List<Candidate> candidates = new ArrayList<>();
        root.path("candidates").forEach(node -> candidates.add(new Candidate(
                node.path("name").asString(), node.path("provider").asString(), node.path("model").asString(),
                node.path("inputPerMTok").asDouble(), node.path("outputPerMTok").asDouble(),
                node.path("temperature").asDouble(Candidate.DEFAULT_TEMPERATURE),
                node.path("minIntervalMs").asLong(0))));
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
