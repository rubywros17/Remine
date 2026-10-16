package com.remine.server.experiment;

import com.remine.server.domain.screenshot.Category;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * 후보 한 번의 실행을 표본 단위로 기록한 CSV(experiment/runs/, gitignore). 파일명이 들어 있어 개인 데이터다.
 * 같은 표본의 두 실행을 비교하려면(고쳐진 것/새로 틀린 것, 하이브리드) 표본별 결과가 필요해서 남긴다.
 * 파일명 규칙: {yyyyMMdd-HHmmss}.prompt-{버전}.{후보 이름}.csv
 */
final class RunCsv {

    static final String HEADER = "filename,expected,alt,predicted,status,called,ocrChars";
    private static final Pattern FILE_NAME = Pattern.compile("^(\\d{8}-\\d{6})\\.prompt-(v\\d+)\\.(.+)\\.csv$");

    private RunCsv() {
    }

    /** 표본 하나의 결과. */
    record Row(String filename, Category expected, Category alt, Category predicted,
               LlmOutcome.Status status, boolean called, int ocrChars) {

        boolean evaluated() {
            return status != LlmOutcome.Status.CALL_FAILED;
        }

        boolean strictCorrect() {
            return predicted == expected;
        }
    }

    /** 실행 한 번: 어떤 후보를 어떤 프롬프트 버전으로 돌렸는지와 표본별 결과. */
    record Run(String candidate, PromptVersion version, String timestamp, List<Row> rows) {
    }

    record FileInfo(String timestamp, PromptVersion version, String candidate) {
    }

    static String fileName(LocalDateTime now, PromptVersion version, String candidate) {
        return now.format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"))
                + ".prompt-" + version.label() + "." + candidate + ".csv";
    }

    static Optional<FileInfo> parseFileName(String name) {
        Matcher m = FILE_NAME.matcher(name);
        if (!m.matches()) {
            return Optional.empty();
        }
        try {
            return Optional.of(new FileInfo(m.group(1), PromptVersion.parse(m.group(2)), m.group(3)));
        } catch (IllegalArgumentException unknownVersion) {
            return Optional.empty();
        }
    }

    static void write(Path file, List<ExperimentStats.Sample> samples) throws IOException {
        Files.createDirectories(file.getParent());
        List<String> lines = new ArrayList<>();
        lines.add(HEADER);
        for (ExperimentStats.Sample s : samples) {
            lines.add(String.join(",", s.filename(), s.expected().name(),
                    s.alt() == null ? "" : s.alt().name(), s.predicted().name(), s.status().name(),
                    String.valueOf(s.called()), String.valueOf(s.ocrChars())));
        }
        Files.write(file, lines, StandardCharsets.UTF_8);
    }

    static List<Row> read(Path file) throws IOException {
        List<Row> rows = new ArrayList<>();
        for (String line : Files.readAllLines(file, StandardCharsets.UTF_8).stream().skip(1).toList()) {
            if (!line.contains(",")) {
                continue;
            }
            String[] parts = line.split(",", -1);
            if (parts.length < 7) {
                continue;
            }
            int n = parts.length;
            String filename = String.join(",", Arrays.copyOfRange(parts, 0, n - 6));
            rows.add(new Row(filename, Category.valueOf(parts[n - 6]),
                    parts[n - 5].isEmpty() ? null : Category.valueOf(parts[n - 5]),
                    Category.valueOf(parts[n - 4]), LlmOutcome.Status.valueOf(parts[n - 3]),
                    Boolean.parseBoolean(parts[n - 2]), Integer.parseInt(parts[n - 1])));
        }
        return rows;
    }

    /** runs/ 안에서 (버전, 후보)에 해당하는 가장 최근 실행. 타임스탬프가 파일명 앞에 있어 이름순이 시간순이다. */
    static Optional<Run> latest(Path runsDir, PromptVersion version, String candidate) throws IOException {
        if (!Files.isDirectory(runsDir)) {
            return Optional.empty();
        }
        Path latest = null;
        FileInfo latestInfo = null;
        try (Stream<Path> files = Files.list(runsDir)) {
            for (Path file : files.toList()) {
                Optional<FileInfo> info = parseFileName(file.getFileName().toString());
                if (info.isPresent() && info.get().version() == version && info.get().candidate().equals(candidate)
                        && (latestInfo == null || info.get().timestamp().compareTo(latestInfo.timestamp()) > 0)) {
                    latest = file;
                    latestInfo = info.get();
                }
            }
        }
        if (latest == null) {
            return Optional.empty();
        }
        return Optional.of(new Run(candidate, version, latestInfo.timestamp(), read(latest)));
    }
}
