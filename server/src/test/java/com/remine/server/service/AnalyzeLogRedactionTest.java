package com.remine.server.service;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.ThrowableProxyUtil;
import ch.qos.logback.core.read.ListAppender;
import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.classifier.UsageMeter;
import com.remine.server.classifier.llm.HybridLlmClassifier;
import com.remine.server.classifier.llm.LlmClassifier;
import com.remine.server.classifier.llm.LlmProvider;
import com.remine.server.classifier.llm.LlmReply;
import com.remine.server.classifier.llm.PromptVersion;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.AnalyzeResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * analyze 경로의 로그에는 건수·상태·소요 시간만 남고 OCR 원문·이미지·키·제공사 오류/모델 출력이 없다는 것을 고정한다.
 * (성공·호출 실패·해석 불가 응답이 섞인 배치를 실제 HybridLlmClassifier + 가짜 제공사로 돌리고 모든 로그 이벤트를 검사한다.)
 */
class AnalyzeLogRedactionTest {

    private static final String SECRET_KEY = "DUMMY_SECRET_KEY_VALUE";
    private static final String SECRET_OCR_FAIL = "SECRET_OCR_CALL_FAIL";
    private static final String SECRET_OCR_GARBAGE = "SECRET_OCR_GARBAGE";
    private static final String SECRET_OCR_OK = "SECRET_OCR_OK";
    private static final String SECRET_MODEL_OUTPUT = "SECRET_MODEL_OUTPUT_TEXT";
    private static final byte[] SECRET_IMAGE = "SECRET_IMAGE_BYTES".getBytes(StandardCharsets.UTF_8);

    private final ListAppender<ILoggingEvent> appender = new ListAppender<>();
    private final Logger root = (Logger) LoggerFactory.getLogger(Logger.ROOT_LOGGER_NAME);
    private Level originalLevel;

    @BeforeEach
    void attachAppender() {
        originalLevel = root.getLevel();
        root.setLevel(Level.TRACE); // 디버그·트레이스 로그까지 잡는다
        appender.start();
        root.addAppender(appender);
    }

    @AfterEach
    void detachAppender() {
        root.detachAppender(appender);
        root.setLevel(originalLevel);
    }

    private String allLogText() {
        return appender.list.stream().map(event -> event.getFormattedMessage() + " "
                        + java.util.Arrays.toString(event.getArgumentArray()) + " "
                        + (event.getThrowableProxy() == null ? "" : ThrowableProxyUtil.asString(event.getThrowableProxy())))
                .collect(Collectors.joining("\n"));
    }

    private HybridLlmClassifier hybridWithFakeProvider() {
        LlmProvider provider = new LlmProvider() {
            @Override
            public LlmReply call(String model, String systemPrompt, String userText) {
                return reply(userText);
            }

            @Override
            public LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
                return reply(userText);
            }

            private LlmReply reply(String userText) {
                if (userText.contains(SECRET_OCR_FAIL)) {
                    // 최악의 경우를 흉내: 제공사 오류 본문에 키와 OCR 원문이 에코되어 있다 (400은 재시도 없이 바로 실패)
                    String body = "{\"error\":{\"code\":400,\"status\":\"INVALID_ARGUMENT\",\"message\":\"key="
                            + SECRET_KEY + " text=" + userText + "\"}}";
                    throw HttpClientErrorException.create(HttpStatus.BAD_REQUEST, "Bad Request", new HttpHeaders(),
                            body.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
                }
                if (userText.contains(SECRET_OCR_GARBAGE)) {
                    return new LlmReply(SECRET_MODEL_OUTPUT + " 이건 JSON이 아니다", 10, 5);
                }
                return new LlmReply("{\"category\":\"INFO\",\"tags\":[\"팁\"],\"summary\":\"" + SECRET_MODEL_OUTPUT + "\"}", 10, 5);
            }
        };
        LlmClassifier llm = new LlmClassifier("m", 0, provider, JsonMapper.builder().build(), PromptVersion.V1);
        return new HybridLlmClassifier(llm, 150);
    }

    @Test
    void 성공_실패_해석불가가_섞인_배치의_로그에는_원문_이미지_키_오류본문이_없다() {
        DeviceRepository deviceRepository = mock(DeviceRepository.class);
        ScreenshotRepository screenshotRepository = mock(ScreenshotRepository.class);
        ScreenshotPersister persister = mock(ScreenshotPersister.class);
        when(deviceRepository.existsById(any())).thenReturn(true);
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        RemineProperties properties = new RemineProperties(RemineProperties.ClassifierType.GEMINI,
                new RemineProperties.Llm(150, new RemineProperties.Gemini("m", 1.0, "http://localhost:1",
                        Duration.ofSeconds(1), Duration.ofSeconds(1), 0), new RemineProperties.Batch(10, 5)),
                new RemineProperties.Analyze(20),
                new RemineProperties.Image(1048576, 1024, 25_000_000L, 12582912, 5242880),
                new RemineProperties.Tags(List.of()),
                new RemineProperties.Interest(14, 3, 28));
        HybridLlmClassifier classifier = hybridWithFakeProvider();
        ScreenshotService service = new ScreenshotService(deviceRepository, screenshotRepository, classifier, persister,
                properties, new TagCleaner(properties), new UsageMeter());
        LocalDateTime now = LocalDateTime.of(2026, 10, 19, 12, 0);

        AnalyzeResponse response = service.analyze(1L, new AnalyzeRequest(List.of(
                new Item("ok", now, "앱", SECRET_OCR_OK),
                new Item("fail", now, "앱", SECRET_OCR_FAIL),
                new Item("garbage", now, "앱", SECRET_OCR_GARBAGE))));
        classifier.classify(SECRET_OCR_OK, SECRET_IMAGE); // 이미지 경로(성공)의 로그도 검사
        assertThatThrownBy(() -> classifier.classify(SECRET_OCR_FAIL, SECRET_IMAGE)) // 이미지 경로(실패)
                .isInstanceOf(ClassificationException.class)
                .satisfies(e -> assertThat(e.getMessage()).doesNotContain(SECRET_KEY).doesNotContain(SECRET_OCR_FAIL));

        String logs = allLogText();
        assertThat(response.analyzed()).hasSize(1);
        assertThat(response.failed()).hasSize(2);
        assertThat(logs).contains("requested=3").contains("analyzed=1").contains("failed=2");
        assertThat(logs)
                .doesNotContain(SECRET_KEY)
                .doesNotContain(SECRET_OCR_OK).doesNotContain(SECRET_OCR_FAIL).doesNotContain(SECRET_OCR_GARBAGE)
                .doesNotContain(SECRET_MODEL_OUTPUT)
                .doesNotContain("SECRET_IMAGE_BYTES")
                .doesNotContain(Base64.getEncoder().encodeToString(SECRET_IMAGE));
    }
}
