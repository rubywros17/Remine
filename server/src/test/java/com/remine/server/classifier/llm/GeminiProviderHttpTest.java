package com.remine.server.classifier.llm;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.IntFunction;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 실제 HTTP 경로(RestClient)를 로컬 가짜 서버로 검증한다. baseUrl을 주입하므로 이 테스트들은 외부 네트워크에 나가지 않는다.
 * (키는 테스트용 더미 값이다.)
 */
class GeminiProviderHttpTest {

    private static final String DUMMY_KEY = "dummy-test-key";
    private static final String OK_BODY = """
            {"candidates":[{"content":{"parts":[{"text":"{\\"category\\":\\"PLACE\\",\\"tags\\":[\\"카페\\"],\\"summary\\":\\"요약\\"}"}]},
                            "finishReason":"STOP"}],
             "usageMetadata":{"promptTokenCount":120,"candidatesTokenCount":15}}
            """;

    private final JsonMapper mapper = JsonMapper.builder().build();
    private final List<Request> requests = new CopyOnWriteArrayList<>();
    private HttpServer server;
    private IntFunction<Response> responder = n -> new Response(200, OK_BODY, 0);

    record Request(String path, String keyHeader, String body) {
    }

    record Response(int status, String body, long delayMillis) {
    }

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            requests.add(new Request(exchange.getRequestURI().getPath(),
                    exchange.getRequestHeaders().getFirst("x-goog-api-key"), body));
            Response response = responder.apply(requests.size());
            try {
                Thread.sleep(response.delayMillis());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            byte[] bytes = response.body().getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(response.status(), bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    private String baseUrl() {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    private GeminiProvider provider(String base, Duration readTimeout) {
        return new GeminiProvider(DUMMY_KEY, 1.0, mapper, base, Duration.ofSeconds(2), readTimeout);
    }

    private LlmClassifier classifier(GeminiProvider provider, List<Long> sleeps) {
        return new LlmClassifier("m", 0, provider, mapper, PromptVersion.V1, sleeps::add, System::nanoTime);
    }

    @Test
    void 키는_헤더로_보내고_모델_경로와_요청_본문이_맞다() {
        LlmReply reply = provider(baseUrl(), Duration.ofSeconds(5)).call("gemini-x", "시스템", "OCR 본문");

        assertThat(reply.text()).contains("PLACE");
        assertThat(reply.inputTokens()).isEqualTo(120);
        Request request = requests.get(0);
        assertThat(request.path()).isEqualTo("/v1beta/models/gemini-x:generateContent");
        assertThat(request.keyHeader()).isEqualTo(DUMMY_KEY);
        assertThat(request.path()).doesNotContain(DUMMY_KEY); // 키가 URL에 실리지 않는다
        JsonNode body = mapper.readTree(request.body());
        assertThat(body.path("generationConfig").path("temperature").asDouble(-1)).isEqualTo(1.0);
        assertThat(body.path("contents").path(0).path("parts").path(0).path("text").asString()).isEqualTo("OCR 본문");
        assertThat(body.path("contents").path(0).path("parts").size()).isEqualTo(1);
    }

    @Test
    void 이미지를_함께_보내면_inlineData가_붙는다() {
        provider(baseUrl(), Duration.ofSeconds(5)).call("m", "시스템", "OCR", new byte[]{(byte) 0xFF, (byte) 0xD8, 1});

        JsonNode parts = mapper.readTree(requests.get(0).body()).path("contents").path(0).path("parts");
        assertThat(parts.size()).isEqualTo(2);
        assertThat(parts.path(1).path("inlineData").path("mimeType").asString()).isEqualTo("image/jpeg");
    }

    @Test
    void baseUrl_끝의_슬래시는_무시한다() {
        provider(baseUrl() + "/", Duration.ofSeconds(5)).call("m", "s", "u");

        assertThat(requests.get(0).path()).isEqualTo("/v1beta/models/m:generateContent");
    }

    @Test
    void 잘못된_키_400은_재시도하지_않고_요약에_본문이_없다() {
        responder = n -> new Response(400,
                "{\"error\":{\"code\":400,\"message\":\"API key not valid. Please pass a valid API key.\","
                        + "\"status\":\"INVALID_ARGUMENT\"}}", 0);
        List<Long> sleeps = new ArrayList<>();

        LlmOutcome outcome = classifier(provider(baseUrl(), Duration.ofSeconds(5)), sleeps).classifyWithUsage("OCR 본문");

        assertThat(requests).hasSize(1);
        assertThat(sleeps).isEmpty();
        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.CALL_FAILED);
        assertThat(outcome.giveUp()).isTrue();
        assertThat(outcome.summary()).contains("HTTP 400 INVALID_ARGUMENT").doesNotContain("API key");
        assertThat(outcome.summary()).doesNotContain(DUMMY_KEY).doesNotContain("OCR 본문");
    }

    @Test
    void 쿼터_초과_429는_서버가_알려_준_시간을_기다렸다가_재시도한다() {
        responder = n -> n == 1
                ? new Response(429, "{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\",\"details\":["
                        + "{\"@type\":\"type.googleapis.com/google.rpc.RetryInfo\",\"retryDelay\":\"7s\"}]}}", 0)
                : new Response(200, OK_BODY, 0);
        List<Long> sleeps = new ArrayList<>();

        LlmOutcome outcome = classifier(provider(baseUrl(), Duration.ofSeconds(5)), sleeps).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.OK);
        assertThat(requests).hasSize(2);
        assertThat(sleeps).containsExactly(8_000L); // 7초 + 여유 1초
    }

    @Test
    void 읽기_타임아웃이_적용되어_응답이_없으면_실패로_끝난다() {
        responder = n -> new Response(200, OK_BODY, 600);
        List<Long> sleeps = new ArrayList<>();

        LlmOutcome outcome = classifier(provider(baseUrl(), Duration.ofMillis(150)), sleeps).classifyWithUsage("x");

        assertThat(outcome.status()).isEqualTo(LlmOutcome.Status.CALL_FAILED);
        assertThat(outcome.summary()).contains("시도 " + LlmClassifier.MAX_ATTEMPTS + "회");
        assertThat(sleeps).hasSize(LlmClassifier.MAX_ATTEMPTS - 1); // 통신 오류는 재시도 대상
    }
}
