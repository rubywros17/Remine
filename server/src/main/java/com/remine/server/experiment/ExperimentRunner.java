package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.experiment.ExperimentStats.Sample;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
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
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
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
    private final String promptOption;
    private final String compareOption;
    private final ProviderFactory providerFactory;
    private final JsonMapper mapper = JsonMapper.builder().build();
    private final Map<String, byte[]> imageCache = new HashMap<>();

    /** 후보의 API 호출 구현을 만든다. 키가 없으면 비어 있다. 테스트에서 가짜로 바꿔 끼운다. */
    interface ProviderFactory {
        Optional<LlmProvider> create(Candidate candidate, JsonMapper mapper);
    }

    /** 호출 실패 비율이 이를 넘으면 그 후보의 실행은 불완전하다고 보고 결과를 쓰지 않는다. */
    static final double MAX_FAILED_CALL_RATIO = 0.10;
    /** 다시 시도해도 소용없는 실패(잘못된 키 등)가 연속으로 이만큼 나오면 그 후보를 바로 중단한다. */
    static final int MAX_CONSECUTIVE_GIVE_UPS = 3;

    /**
     * limit: --experiment.limit=N. 0(기본)이면 전체 표본. 형식 검증용 소량 실행에 쓴다.
     * candidatesFilter: --experiment.candidates=모델ID[,모델ID]. 비어 있으면 candidates.json의 전체 후보.
     * promptOption: --experiment.prompt=v1|v2. 비어 있으면 v1(운영 프롬프트). v2는 채택 안 됨(SHOPPING 회귀)이라 실험 옵션이다.
     * compareOption: --experiment.compare=v1,v2. 지정하면 API를 호출하지 않고 저장된 실행(runs/)끼리 비교만 한다.
     */
    @Autowired
    ExperimentRunner(@Value("${experiment.dir:../experiment}") String dir,
                     @Value("${experiment.limit:0}") int limit,
                     @Value("${experiment.candidates:}") String candidatesFilter,
                     @Value("${experiment.prompt:}") String promptOption,
                     @Value("${experiment.compare:}") String compareOption,
                     Environment environment) {
        // 키는 System.getenv가 아니라 스프링 Environment에서 읽는다: 환경변수(우선) 또는 ~/.remine.env
        // (application-experiment.yaml의 spring.config.import). 값은 출력하지 않는다.
        this(dir, limit, candidatesFilter, promptOption, compareOption,
                (candidate, mapper) -> LlmProviders.create(candidate, mapper, environment::getProperty));
    }

    ExperimentRunner(String dir, int limit, String candidatesFilter, String promptOption, String compareOption,
                     ProviderFactory providerFactory) {
        this.dir = Path.of(dir);
        this.limit = limit;
        this.candidatesFilter = candidatesFilter;
        this.promptOption = promptOption;
        this.compareOption = compareOption;
        this.providerFactory = providerFactory;
    }

    @Override
    public void run(String... args) throws IOException {
        if (!compareOption.isBlank()) {
            compareRuns();
            return;
        }
        PromptVersion promptVersion;
        try {
            promptVersion = PromptVersion.parse(promptOption);
        } catch (IllegalArgumentException e) {
            log.error(e.getMessage());
            return;
        }
        List<Candidate> available = loadCandidates();
        List<Candidate> candidates;
        try {
            candidates = filterCandidates(available, candidatesFilter);
        } catch (IllegalArgumentException e) {
            log.error(e.getMessage());
            return;
        }
        boolean filtered = candidates.size() < available.size();

        // 표본·이미지를 읽거나 API를 부르기 전에 키부터 확인한다. 키 값이나 길이는 출력하지 않는다.
        Map<Candidate, LlmProvider> providers = new LinkedHashMap<>();
        List<String> skipped = new ArrayList<>();
        for (Candidate candidate : candidates) {
            providerFactory.create(candidate, mapper).ifPresentOrElse(
                    provider -> providers.put(candidate, provider),
                    () -> skipped.add(candidate.name() + " (" + LlmProviders.envName(candidate.provider()) + ")"));
        }
        if (providers.isEmpty()) {
            log.error("API 키가 없거나 비어 있어 실행하지 않습니다. 환경변수 또는 ~/.remine.env 파일에 설정하세요: {}",
                    candidates.stream().map(c -> LlmProviders.envName(c.provider())).distinct().toList());
            return;
        }
        log.info("API 키 확인: 후보 {}개 중 {}개에 키가 있습니다.", candidates.size(), providers.size());

        List<Labeled> all = new ArrayList<>();
        int unlabeled = loadLabels(all);
        List<Labeled> labeled = applyLimit(all, limit);
        if (labeled.isEmpty()) {
            log.warn("평가할 표본이 없습니다. ocr.sh를 실행하고 labels.csv의 category를 채우세요. (dir={})",
                    dir.toAbsolutePath());
            return;
        }
        boolean limited = limit > 0;
        log.info("프롬프트 {}, 표본 {}장{}, 후보 {}개", promptVersion.label(), labeled.size(),
                limited ? " (전체 " + all.size() + "장 중 제한 실행)" : "", candidates.size());

        List<ExperimentStats.Report> reports = new ArrayList<>();
        StringBuilder errors = new StringBuilder("# 오답 상세 (개인 데이터, 커밋 금지)\n");
        boolean attempted = false;

        for (Map.Entry<Candidate, LlmProvider> entry : providers.entrySet()) {
            Candidate candidate = entry.getKey();
            LlmClassifier classifier = new LlmClassifier(candidate, entry.getValue(), mapper, promptVersion);
            List<Sample> samples = new ArrayList<>();
            int calls = 0;
            int failedCalls = 0;
            int consecutiveGiveUps = 0;
            boolean aborted = false;
            for (Labeled item : labeled) {
                Classified classified = classify(classifier, item);
                Sample sample = classified.sample();
                samples.add(sample);
                if (sample.called()) {
                    calls++;
                    if (sample.status() == LlmOutcome.Status.CALL_FAILED) {
                        failedCalls++;
                        consecutiveGiveUps = classified.giveUp() ? consecutiveGiveUps + 1 : 0;
                    } else {
                        consecutiveGiveUps = 0;
                    }
                }
                if (limited) {
                    logSample(candidate, sample);
                } else if (samples.size() % 10 == 0) {
                    log.info("{}: {}/{}", candidate.name(), samples.size(), labeled.size());
                }
                if (consecutiveGiveUps >= MAX_CONSECUTIVE_GIVE_UPS) {
                    // 같은 이유로 계속 실패할 호출(잘못된 키, 소진된 쿼터)을 남은 표본만큼 반복하지 않는다.
                    aborted = true;
                    log.error("{}: 재시도해도 소용없는 호출 실패가 연속 {}건 발생해 중단합니다. 원인은 오답 상세 파일에서 확인하세요.",
                            candidate.name(), consecutiveGiveUps);
                    break;
                }
            }
            attempted = true;
            ExperimentStats.Report report = ExperimentStats.summarize(candidate, samples);
            appendErrors(errors, candidate, samples);
            String incomplete = incompleteReason(calls, failedCalls, aborted);
            if (incomplete != null) {
                // 호출 대부분이 실패한 실행은 정확도에 쓸 수 없고, 비교(compare)의 "최신 실행"을 오염시키므로 결과·기록을 쓰지 않는다.
                skipped.add(candidate.name() + " (" + incomplete + ")");
                continue;
            }
            if (report.evaluated() == 0) {
                // 호출이 전부 실패해 평가된 표본이 없다. 빈 표가 결과 파일에 들어가지 않게 제외한다.
                skipped.add(candidate.name() + " (호출 " + report.callFailed() + "건 전부 실패)");
                continue;
            }
            reports.add(report);
            if (!limited) {
                // 표본별 결과를 남겨 두면 나중에 다른 프롬프트 버전과 표본 단위로 비교할 수 있다(gitignore).
                RunCsv.write(dir.resolve("runs").resolve(
                        RunCsv.fileName(LocalDateTime.now(), promptVersion, candidate.name())), samples);
            }
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

        // 프롬프트 버전이 파일명에 들어가므로 다른 버전의 결과를 덮어쓰지 않는다.
        Path resultsFile = dir.resolve(resultsFileName(promptVersion, limited, filtered, reports));
        Files.writeString(resultsFile,
                ResultsMarkdown.render(promptVersion, LocalDate.now(), labeled.size(), unlabeled, reports, skipped),
                StandardCharsets.UTF_8);
        Path errorsFile = uniqueErrorsFile(LocalDateTime.now());
        Files.writeString(errorsFile, errors.toString(), StandardCharsets.UTF_8);
        log.info("완료: {} (후보 {}개 평가, {}개 건너뜀), 오답 상세: {}", resultsFile.toAbsolutePath(),
                reports.size(), skipped.size(), errorsFile.getFileName());
    }

    /**
     * 저장된 실행(runs/)에서 후보별 최신 실행을 두 프롬프트 버전끼리 비교해 리포트를 쓴다. API 호출은 없다.
     * 텍스트 후보와 같은 모델의 이미지 후보가 둘 다 있으면 하이브리드도 계산한다.
     */
    private void compareRuns() throws IOException {
        String[] versions = compareOption.split(",");
        PromptVersion base;
        PromptVersion next;
        try {
            if (versions.length != 2) {
                throw new IllegalArgumentException("--experiment.compare=v1,v2 형식이어야 합니다: '" + compareOption + "'");
            }
            base = PromptVersion.parse(versions[0]);
            next = PromptVersion.parse(versions[1]);
        } catch (IllegalArgumentException e) {
            log.error(e.getMessage());
            return;
        }

        List<Candidate> candidates = loadCandidates();
        Path runsDir = dir.resolve("runs");
        Map<String, RunCsv.Run[]> runs = new LinkedHashMap<>();
        Map<String, Candidate> byName = new HashMap<>();
        for (Candidate candidate : candidates) {
            var baseRun = RunCsv.latest(runsDir, base, candidate.name());
            var nextRun = RunCsv.latest(runsDir, next, candidate.name());
            if (baseRun.isPresent() && nextRun.isPresent()) {
                runs.put(candidate.name(), new RunCsv.Run[]{baseRun.get(), nextRun.get()});
                byName.put(candidate.name(), candidate);
            } else if (baseRun.isPresent() || nextRun.isPresent()) {
                log.warn("{}: {} / {} 중 한쪽 실행만 있어 비교에서 제외했습니다.", candidate.name(), base.label(), next.label());
            }
        }
        if (runs.isEmpty()) {
            log.warn("비교할 실행이 없습니다. {} / {} 를 같은 후보로 각각 한 번 이상 돌려야 합니다. (dir={})",
                    base.label(), next.label(), runsDir.toAbsolutePath());
            return;
        }

        List<RunComparison.Pair> overall = new ArrayList<>();
        runs.forEach((name, pair) -> overall.add(new RunComparison.Pair(
                (byName.get(name).usesImage() ? "텍스트 + 이미지 " : "텍스트만 ") + "(" + name + ")",
                RunComparison.accuracy(pair[0]), RunComparison.accuracy(pair[1]))));
        for (Candidate text : candidates) {
            candidates.stream()
                    .filter(image -> text.input() == InputMode.TEXT && image.usesImage()
                            && image.model().equals(text.model())
                            && runs.containsKey(text.name()) && runs.containsKey(image.name()))
                    .findFirst()
                    .ifPresent(image -> overall.add(new RunComparison.Pair(
                            "하이브리드 " + RunComparison.HYBRID_THRESHOLD_CHARS + "자 (" + text.model() + ")",
                            RunComparison.hybrid(runs.get(text.name())[0], runs.get(image.name())[0],
                                    RunComparison.HYBRID_THRESHOLD_CHARS),
                            RunComparison.hybrid(runs.get(text.name())[1], runs.get(image.name())[1],
                                    RunComparison.HYBRID_THRESHOLD_CHARS))));
        }

        String suffix = "prompt-" + base.label() + "-vs-prompt-" + next.label();
        Path summaryFile = dir.resolve("results.compare." + suffix + ".md");
        Path localFile = dir.resolve("compare.local." + suffix + ".md");
        Files.writeString(summaryFile, RunComparison.renderSummary(base, next, overall, runs,
                RunComparison.HYBRID_THRESHOLD_CHARS), StandardCharsets.UTF_8);
        Files.writeString(localFile, RunComparison.renderLocal(base, next, runs), StandardCharsets.UTF_8);
        log.info("비교 완료: {} (표본별 목록: {})", summaryFile.toAbsolutePath(), localFile.getFileName());
    }

    /**
     * 결과 파일명에는 프롬프트 버전이 들어간다. 전체 실행은 results.prompt-v2.md,
     * 후보 지정 실행은 results.prompt-v2.{후보}.md라서 다른 후보·다른 버전의 결과를 지우지 않는다.
     * 표본 제한 실행은 버전과 무관하게 results.limit.md(gitignore)다.
     * 버전 접두어가 없는 기존 results.*.md는 프롬프트 버전 도입 전(v1) 결과다.
     */
    static String resultsFileName(PromptVersion version, boolean limited, boolean filtered,
                                  List<ExperimentStats.Report> reports) {
        if (limited) {
            return "results.limit.md";
        }
        String prefix = "results.prompt-" + version.label();
        if (filtered) {
            // 이름에 "+image"가 들어갈 수 있어 구분자는 "__"를 쓴다.
            return prefix + "." + reports.stream().map(r -> r.candidate().name()).collect(Collectors.joining("__")) + ".md";
        }
        return prefix + ".md";
    }

    /**
     * filter는 쉼표로 구분한 모델 ID 또는 후보 이름. 비어 있으면 전체. 모르는 값이 있으면 예외.
     * 후보 이름과 정확히 같으면 그 후보만(예: gemini-3.5-flash-lite → 텍스트 변형,
     * gemini-3.5-flash-lite+image → 이미지 변형), 이름이 아니면 모델 ID가 같은 변형을 모두 고른다.
     */
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
            // 후보 이름이 정확히 같으면 그 후보만, 없으면 모델 ID가 같은 후보(텍스트·이미지 변형)를 모두 고른다.
            List<Candidate> byName = available.stream().filter(c -> c.name().equalsIgnoreCase(wanted)).toList();
            List<Candidate> matches = !byName.isEmpty() ? byName : available.stream()
                    .filter(c -> c.model().equalsIgnoreCase(wanted))
                    .toList();
            if (matches.isEmpty()) {
                unknown.add(wanted);
            }
            matches.stream().filter(c -> !selected.contains(c)).forEach(selected::add);
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

    /**
     * 불완전한 실행이면 그 사유, 아니면 null. 실제로 API를 부른 표본(calls) 기준이다.
     * 중단됐거나 호출 실패가 10%를 넘으면 불완전하다. (OCR이 비어 호출하지 않은 표본은 세지 않는다)
     */
    static String incompleteReason(int calls, int failedCalls, boolean aborted) {
        if (aborted) {
            return "재시도 불가 오류가 연속 " + MAX_CONSECUTIVE_GIVE_UPS + "건 발생해 중단, 호출 실패 "
                    + failedCalls + "/" + calls + "건";
        }
        if (calls > 0 && failedCalls > calls * MAX_FAILED_CALL_RATIO) {
            return "호출 실패 " + failedCalls + "/" + calls + "건(10% 초과)으로 불완전한 실행";
        }
        return null;
    }

    // 형식 검증용: 건별 상태·토큰·시간·원문 앞부분을 콘솔에만 출력한다(파일에는 남기지 않음).
    private void logSample(Candidate candidate, Sample s) {
        log.info("[{}] {} → 예측 {} (정답 {}) status={} 토큰 {}/{} {}ms | {}",
                candidate.name(), s.filename(), s.predicted(), s.expected(), s.status(),
                s.usage().inputTokens(), s.usage().outputTokens(), s.usage().latencyMs(), oneLine(s.detail()));
    }

    /** 분류 한 건의 표본 결과와, 다시 시도해도 소용없는 실패(giveUp)였는지. */
    private record Classified(Sample sample, boolean giveUp) {
    }

    private Classified classify(LlmClassifier classifier, Labeled item) {
        int ocrChars = Sample.countChars(item.ocrText());
        byte[] image = null;
        if (classifier.candidate().usesImage()) {
            // text+image 후보: 실험 러너 전용. 글자가 없는 스크린샷도 이미지를 보고 분류해 볼 수 있으므로 호출한다.
            try {
                image = resizedImage(item.filename());
            } catch (IOException e) {
                return new Classified(new Sample(item.filename(), item.expected(), item.alt(), Category.ETC,
                        LlmOutcome.Status.CALL_FAILED, false, LlmUsage.NONE, "이미지 로드 실패: " + e.getMessage(),
                        ocrChars), false);
            }
        } else if (item.ocrText().isBlank()) {
            // 서버와 같은 규칙: 글자가 없으면 LLM을 부르지 않고 ETC.
            return new Classified(new Sample(item.filename(), item.expected(), item.alt(), Category.ETC,
                    LlmOutcome.Status.OK, false, LlmUsage.NONE, "", 0), false);
        }
        LlmOutcome outcome = classifier.classifyWithUsage(item.ocrText(), image);
        return new Classified(new Sample(item.filename(), item.expected(), item.alt(), outcome.result().category(),
                outcome.status(), true, outcome.usage(), outcome.raw(), ocrChars), outcome.giveUp());
    }

    // 같은 이미지를 여러 후보·재시도에서 다시 줄이지 않도록 한 번만 줄여 둔다.
    private byte[] resizedImage(String filename) throws IOException {
        byte[] cached = imageCache.get(filename);
        if (cached == null) {
            cached = ImageResizer.toJpeg(dir.resolve("images").resolve(filename), ImageResizer.DEFAULT_MAX_LONG_SIDE);
            imageCache.put(filename, cached);
        }
        return cached;
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
                node.path("minIntervalMs").asLong(0),
                InputMode.parse(node.path("input").asString("")))));
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
