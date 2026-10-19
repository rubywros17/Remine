package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 하이브리드 분기: OCR이 짧고 이미지가 있을 때만 이미지를 보낸다. 실제 API 호출은 없다(가짜 제공사). */
class HybridLlmClassifierTest {

    private static final String OK_REPLY = "{\"category\":\"PLACE\",\"tags\":[\"카페\"],\"summary\":\"요약\"}";
    private static final byte[] IMAGE = {1, 2, 3};

    private final JsonMapper mapper = JsonMapper.builder().build();

    /** 텍스트 호출과 이미지 호출을 구분해 기록하는 가짜 제공사. */
    private static final class RecordingProvider implements LlmProvider {
        final List<String> textCalls = new ArrayList<>();
        final List<byte[]> imageCalls = new ArrayList<>();
        final Supplier<LlmReply> reply;

        RecordingProvider(Supplier<LlmReply> reply) {
            this.reply = reply;
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText) {
            textCalls.add(userText);
            return reply.get();
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
            imageCalls.add(jpegImage);
            return reply.get();
        }
    }

    private RecordingProvider okProvider() {
        return new RecordingProvider(() -> new LlmReply(OK_REPLY, 10, 5));
    }

    private HybridLlmClassifier classifier(LlmProvider provider, int threshold) {
        LlmClassifier llm = new LlmClassifier("m", 0, provider, mapper, PromptVersion.V1, ms -> { }, System::nanoTime);
        return new HybridLlmClassifier(llm, threshold);
    }

    @Test
    void 글자_수가_기준값_미만이고_이미지가_있으면_이미지도_함께_보낸다() {
        RecordingProvider provider = okProvider();

        ClassificationResult result = classifier(provider, 150).classify("가".repeat(149), IMAGE);

        assertThat(provider.imageCalls).hasSize(1);
        assertThat(provider.textCalls).isEmpty();
        assertThat(result.category()).isEqualTo(Category.PLACE);
    }

    @Test
    void 글자_수가_기준값과_같으면_텍스트만_보낸다() {
        RecordingProvider provider = okProvider();

        classifier(provider, 150).classify("가".repeat(150), IMAGE);

        assertThat(provider.textCalls).hasSize(1);
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 이미지가_없으면_글자가_짧아도_텍스트만_보낸다() {
        RecordingProvider provider = okProvider();

        classifier(provider, 150).classify("짧음", null);
        classifier(provider, 150).classify("짧음", new byte[0]);
        classifier(provider, 150).classify("짧음");

        assertThat(provider.textCalls).hasSize(3);
        assertThat(provider.imageCalls).isEmpty();
    }

    @Test
    void 공백은_글자_수에서_빼고_센다() {
        RecordingProvider provider = okProvider();
        String spaced = ("가 ".repeat(100)) + "\n\n\n"; // 공백 포함 길이는 200을 넘지만 글자는 100자

        classifier(provider, 150).classify(spaced, IMAGE);

        assertThat(provider.imageCalls).hasSize(1);
    }

    @Test
    void 기준값은_설정으로_바꿀_수_있다() {
        RecordingProvider provider = okProvider();
        HybridLlmClassifier strict = classifier(provider, 10);

        strict.classify("가".repeat(10), IMAGE);  // 10자 = 기준값 → 텍스트만
        strict.classify("가".repeat(9), IMAGE);   // 9자 → 이미지

        assertThat(strict.imageThresholdChars()).isEqualTo(10);
        assertThat(provider.textCalls).hasSize(1);
        assertThat(provider.imageCalls).hasSize(1);
    }

    @Test
    void 호출_실패는_예외로_알리고_메시지에_본문과_OCR_원문이_없다() {
        String secretOcr = "비밀 OCR 원문 123456";
        String providerBody = "{\"error\":{\"code\":400,\"message\":\"API key not valid. ...\",\"status\":\"INVALID_ARGUMENT\"}}";
        RecordingProvider provider = new RecordingProvider(() -> {
            throw HttpClientErrorException.create(HttpStatus.BAD_REQUEST, "Bad Request", new HttpHeaders(),
                    providerBody.getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        });

        assertThatThrownBy(() -> classifier(provider, 150).classify(secretOcr, null))
                .isInstanceOfSatisfying(ClassificationException.class, e -> {
                    assertThat(e.reason()).isEqualTo(ClassificationException.Reason.CALL_FAILED);
                    assertThat(e.getMessage()).contains("HTTP 400 INVALID_ARGUMENT")
                            .doesNotContain("API key").doesNotContain(secretOcr);
                });
        assertThat(provider.textCalls).hasSize(1); // 400은 재시도하지 않는다
    }

    @Test
    void 해석할_수_없는_응답은_INVALID_RESPONSE() {
        RecordingProvider provider = new RecordingProvider(() -> new LlmReply("모델이 이상한 말을 했다", 10, 5));

        assertThatThrownBy(() -> classifier(provider, 150).classify("내용", null))
                .isInstanceOfSatisfying(ClassificationException.class, e -> {
                    assertThat(e.reason()).isEqualTo(ClassificationException.Reason.INVALID_RESPONSE);
                    assertThat(e.getMessage()).doesNotContain("이상한 말");
                });
    }

    @Test
    void 범위_밖_카테고리도_ETC로_저장하지_않고_실패로_알린다() {
        RecordingProvider provider = new RecordingProvider(
                () -> new LlmReply("{\"category\":\"FOOD\",\"tags\":[],\"summary\":\"\"}", 10, 5));

        assertThatThrownBy(() -> classifier(provider, 150).classify("내용", null))
                .isInstanceOfSatisfying(ClassificationException.class,
                        e -> assertThat(e.reason()).isEqualTo(ClassificationException.Reason.INVALID_RESPONSE));
    }

    @Test
    void 이미지_판정_표() {
        HybridLlmClassifier c = classifier(okProvider(), 150);

        assertThat(c.imageDecision("")).isEqualTo(com.remine.server.classifier.ImageDecision.USE);
        assertThat(c.imageDecision(null)).isEqualTo(com.remine.server.classifier.ImageDecision.USE);
        assertThat(c.imageDecision("가".repeat(149))).isEqualTo(com.remine.server.classifier.ImageDecision.USE);
        assertThat(c.imageDecision("가".repeat(150))).isEqualTo(com.remine.server.classifier.ImageDecision.ABOVE_THRESHOLD);
        // 마스킹 표시는 짧든 길든 글자 수 조건보다 우선한다
        assertThat(c.imageDecision("연락처 " + com.remine.server.classifier.PrivacyMarkers.PHONE_NUMBER_MASK))
                .isEqualTo(com.remine.server.classifier.ImageDecision.PHONE_MASKED);
        assertThat(c.imageDecision("가".repeat(300) + com.remine.server.classifier.PrivacyMarkers.PHONE_NUMBER_MASK))
                .isEqualTo(com.remine.server.classifier.ImageDecision.PHONE_MASKED);
    }

    @Test
    void 마스킹_표시가_있으면_classify를_직접_불러도_이미지를_보내지_않는다() {
        RecordingProvider provider = okProvider();

        classifier(provider, 150).classify("짧음 " + com.remine.server.classifier.PrivacyMarkers.PHONE_NUMBER_MASK, IMAGE);

        assertThat(provider.imageCalls).isEmpty();
        assertThat(provider.textCalls).hasSize(1);
    }

    @Test
    void 빈_OCR이어도_이미지가_있으면_이미지로_분류한다() {
        RecordingProvider provider = okProvider();

        classifier(provider, 150).classify("", IMAGE);

        assertThat(provider.imageCalls).hasSize(1);
    }
}
