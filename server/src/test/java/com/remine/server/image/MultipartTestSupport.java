package com.remine.server.image;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.ThrowableProxyUtil;
import ch.qos.logback.core.read.ListAppender;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.classifier.llm.HybridLlmClassifier;
import com.remine.server.classifier.llm.LlmClassifier;
import com.remine.server.classifier.llm.LlmProvider;
import com.remine.server.classifier.llm.LlmReply;
import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 실제 Tomcat(RANDOM_PORT)에 JDK HttpClient로 multipart를 직접 보내는 통합 테스트의 공통 도구.
 * MockMvc는 컨테이너의 임시 파일 동작을 재현하지 못하므로 쓰지 않는다. LLM은 가짜 제공사라 외부 호출은 없다.
 *
 * <p>모든 테스트가 끝날 때마다(@AfterEach) 이미지·OCR에 심어 둔 표식이 로그·응답·DB 어디에도 없는지 검사한다.
 */
abstract class MultipartTestSupport {

    /** 이미지 바이트 안(JPEG 주석 세그먼트)에 심는 표식. 서버가 어디에든 남기면 잡힌다. */
    static final String IMAGE_MARKER = "IMG-TRACE-MARKER-9f3a1c";
    /** OCR 텍스트에 심는 표식. */
    static final String OCR_MARKER = "OCR-TRACE-MARKER-7c1d42";

    private static final String OK_REPLY = "{\"category\":\"PLACE\",\"tags\":[\"카페\"],\"summary\":\"요약\"}";

    final JsonMapper json = JsonMapper.builder().build();
    final HttpClient client = HttpClient.newHttpClient();
    final List<String> responseBodies = new CopyOnWriteArrayList<>();

    @Autowired Environment environment;
    @Autowired DeviceRepository deviceRepository;
    @Autowired JdbcTemplate jdbc;
    @Autowired RecordingProvider provider;

    Long deviceId;
    private ListAppender<ILoggingEvent> logs;

    // ---- 설정 ----

    /** 멀티파트 위치와 Tomcat basedir를 이 테스트 전용 폴더로 돌린다 → 새 파일이 생기면 바로 보인다. */
    static void dirProperties(DynamicPropertyRegistry registry, Path multipartDir, Path tomcatDir) {
        registry.add("spring.servlet.multipart.location", multipartDir::toString);
        registry.add("server.tomcat.basedir", tomcatDir::toString);
    }

    static Path newDir(String name) {
        try {
            return Files.createTempDirectory("remine-test-" + name + "-");
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    /** 텍스트/이미지 호출을 기록하고, 호출 도중(=요청 처리 중)에 디스크에 새 파일이 있는지 본다. */
    static final class RecordingProvider implements LlmProvider {
        final List<String> textCalls = new CopyOnWriteArrayList<>();
        final List<byte[]> imageCalls = new CopyOnWriteArrayList<>();
        final List<String> imageCallTexts = new CopyOnWriteArrayList<>();
        final List<String> leakedFiles = new CopyOnWriteArrayList<>();
        private final List<Path> watchedDirs;
        private volatile Set<String> baseline = Set.of();

        RecordingProvider(List<Path> watchedDirs) {
            this.watchedDirs = watchedDirs;
        }

        void reset() {
            textCalls.clear();
            imageCalls.clear();
            imageCallTexts.clear();
            leakedFiles.clear();
            baseline = snapshot();
        }

        Set<String> snapshot() {
            Set<String> files = new java.util.HashSet<>();
            for (Path dir : watchedDirs) {
                if (!Files.isDirectory(dir)) {
                    continue;
                }
                try (Stream<Path> walk = Files.walk(dir)) {
                    walk.filter(Files::isRegularFile).forEach(f -> files.add(f.toString()));
                } catch (IOException e) {
                    throw new IllegalStateException(e);
                }
            }
            // 공용 임시 폴더는 다른 프로세스도 쓰므로 업로드/ImageIO 캐시 이름만 본다
            Path tmp = Path.of(System.getProperty("java.io.tmpdir"));
            try (Stream<Path> list = Files.list(tmp)) {
                list.filter(f -> f.getFileName().toString().matches("(upload_.*|imageio.*)\\.tmp"))
                        .forEach(f -> files.add(f.toString()));
            } catch (IOException e) {
                throw new IllegalStateException(e);
            }
            return files;
        }

        /** baseline 이후 새로 생긴 파일. */
        List<String> newFiles() {
            Set<String> now = snapshot();
            now.removeAll(baseline);
            return new ArrayList<>(now);
        }

        private void probe() {
            leakedFiles.addAll(newFiles());
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText) {
            probe();
            textCalls.add(userText);
            return new LlmReply(OK_REPLY, 10, 5);
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
            probe();
            imageCalls.add(jpegImage.clone());
            imageCallTexts.add(userText);
            return new LlmReply(OK_REPLY, 10, 5);
        }
    }

    @TestConfiguration
    static class Beans {
        @Bean
        RecordingProvider recordingProvider(Environment env) {
            return new RecordingProvider(List.of(
                    Path.of(env.getRequiredProperty("spring.servlet.multipart.location")),
                    Path.of(env.getRequiredProperty("server.tomcat.basedir"))));
        }

        /** 실제 하이브리드 판정 로직 + 가짜 제공사. */
        @Bean
        @Primary
        HybridLlmClassifier hybridClassifier(RecordingProvider provider, JsonMapper mapper, RemineProperties props) {
            LlmClassifier llm = new LlmClassifier("m", 0, provider, mapper, PromptVersion.V1);
            return new HybridLlmClassifier(llm, props.llm().imageThresholdChars());
        }
    }

    // ---- 생명주기: 로그 수집과 흔적 검사 ----

    @BeforeEach
    void setUpTrace() {
        deviceId = deviceRepository.save(new Device("token")).getId();
        provider.reset();
        responseBodies.clear();
        logs = new ListAppender<>();
        logs.start();
        rootLogger().addAppender(logs);
    }

    @AfterEach
    void assertNoTrace() {
        rootLogger().detachAppender(logs);
        List<String> forbidden = forbiddenStrings();

        List<String> logTexts = logs.list.stream().map(e -> {
            String text = e.getFormattedMessage();
            if (e.getThrowableProxy() != null) {
                text += "\n" + ThrowableProxyUtil.asString(e.getThrowableProxy());
            }
            return text;
        }).toList();
        assertContainsNone("로그", logTexts, forbidden);
        assertContainsNone("응답", responseBodies, forbidden);
        // OCR 텍스트는 DB에 저장하는 설계(F-02)라 DB에서는 이미지 흔적만 본다
        assertContainsNone("DB", dumpDb(), forbidden.stream().filter(f -> !f.equals(OCR_MARKER)).toList());
        assertThat(provider.leakedFiles).as("요청 처리 중 생긴 임시 파일").isEmpty();
        assertThat(provider.newFiles()).as("요청이 끝난 뒤 남은 임시 파일").isEmpty();
    }

    private static Logger rootLogger() {
        return (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME);
    }

    /** 표식과 그 base64, 표식이 든 이미지 앞부분의 base64. */
    private static List<String> forbiddenStrings() {
        byte[] sample = jpeg(8, 8, false);
        return List.of(IMAGE_MARKER, OCR_MARKER,
                Base64.getEncoder().encodeToString(IMAGE_MARKER.getBytes(StandardCharsets.UTF_8)),
                Base64.getEncoder().encodeToString(java.util.Arrays.copyOf(sample, 48)));
    }

    private List<String> dumpDb() {
        List<String> dump = new ArrayList<>();
        for (String table : List.of("device", "screenshot", "screenshot_tag", "tag")) {
            dump.add(jdbc.queryForList("select * from " + table).toString());
        }
        return dump;
    }

    private static void assertContainsNone(String where, List<String> texts, List<String> forbidden) {
        for (String text : texts) {
            for (String needle : forbidden) {
                assertThat(text).as(where + "에 흔적이 남았다").doesNotContain(needle);
            }
        }
    }

    // ---- 요청 만들기 ----

    /** 표식이 든 주석(COM) 세그먼트를 가진 JPEG. exif면 EXIF(APP1) 세그먼트도 넣는다. */
    static byte[] jpeg(int width, int height, boolean exif) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        g.setColor(new Color(40, 90, 200));
        g.fillRect(0, 0, width, height);
        g.setColor(Color.WHITE);
        g.fillOval(width / 4, height / 4, width / 2, height / 2);
        g.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            ImageIO.write(image, "jpeg", out);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        byte[] base = out.toByteArray();
        byte[] com = segment(0xFE, IMAGE_MARKER.getBytes(StandardCharsets.UTF_8));
        byte[] exifSegment = exif ? segment(0xE1, ("Exif\0\0GPS-" + IMAGE_MARKER).getBytes(StandardCharsets.UTF_8)) : new byte[0];
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        result.write(base, 0, 2); // SOI
        result.writeBytes(exifSegment);
        result.writeBytes(com);
        result.write(base, 2, base.length - 2);
        return result.toByteArray();
    }

    private static byte[] segment(int marker, byte[] payload) {
        int length = payload.length + 2;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(0xFF);
        out.write(marker);
        out.write(length >> 8);
        out.write(length & 0xFF);
        out.writeBytes(payload);
        return out.toByteArray();
    }

    static BufferedImage decode(byte[] jpeg) {
        try {
            return ImageIO.read(new ByteArrayInputStream(jpeg));
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    static boolean contains(byte[] data, String ascii) {
        return new String(data, StandardCharsets.ISO_8859_1).contains(ascii);
    }

    static String requestJson(String... idAndOcr) {
        // "id|ocr" 형식
        String items = java.util.Arrays.stream(idAndOcr).map(s -> {
            String[] parts = s.split("\\|", 2);
            return "{\"localAssetId\":\"" + parts[0] + "\",\"takenAt\":\"2026-10-19T10:00:00\","
                    + "\"sourceApp\":\"앱\",\"ocrText\":\"" + parts[1] + "\"}";
        }).collect(Collectors.joining(","));
        return "{\"screenshots\":[" + items + "]}";
    }

    /** 손으로 만드는 multipart 본문. */
    static final class Multipart {
        private final String boundary = "----remine" + UUID.randomUUID();
        private final ByteArrayOutputStream out = new ByteArrayOutputStream();

        Multipart text(String name, String value) {
            out.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name + "\"\r\n\r\n")
                    .getBytes(StandardCharsets.UTF_8));
            out.writeBytes(value.getBytes(StandardCharsets.UTF_8));
            out.writeBytes("\r\n".getBytes(StandardCharsets.UTF_8));
            return this;
        }

        Multipart file(String name, byte[] data) {
            out.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name
                    + "\"; filename=\"capture.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n").getBytes(StandardCharsets.UTF_8));
            out.writeBytes(data);
            out.writeBytes("\r\n".getBytes(StandardCharsets.UTF_8));
            return this;
        }

        byte[] body() {
            ByteArrayOutputStream all = new ByteArrayOutputStream();
            all.writeBytes(out.toByteArray());
            all.writeBytes(("--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
            return all.toByteArray();
        }

        String contentType() {
            return "multipart/form-data; boundary=" + boundary;
        }
    }

    record Reply(int status, String body) {
        JsonNode json(JsonMapper mapper) {
            return mapper.readTree(body);
        }
    }

    Reply postMultipart(Multipart multipart) {
        return send(multipart.contentType(), HttpRequest.BodyPublishers.ofByteArray(multipart.body()));
    }

    Reply postJson(String body) {
        return send("application/json", HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));
    }

    private Reply send(String contentType, HttpRequest.BodyPublisher body) {
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(
                            "http://localhost:" + environment.getRequiredProperty("local.server.port") + "/api/screenshots/analyze"))
                    .header("Content-Type", contentType)
                    .header("X-Device-Id", String.valueOf(deviceId))
                    .POST(body).build();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            responseBodies.add(response.body());
            return new Reply(response.statusCode(), response.body());
        } catch (IOException | InterruptedException e) {
            throw new IllegalStateException(e);
        }
    }
}
