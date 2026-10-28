package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.ImageDecision;
import com.remine.server.classifier.UsageMeter;
import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

import static org.assertj.core.api.Assertions.assertThat;

/** 배치 분류: 순번 매칭, 누락분만 단건 재시도, 호출 실패는 재시도 없음, 하이브리드의 텍스트/이미지 묶음. 실제 API 없음. */
class LlmBatchTest {

    private static final String SINGLE_OK = "{\"category\":\"CHAT\",\"tags\":[],\"summary\":\"단건\"}";
    private static final byte[] IMAGE = {1, 2, 3};

    private final JsonMapper mapper = JsonMapper.builder().build();

    /** 배치 호출(조각)과 단건 호출을 기록한다. 배치 응답은 조각 목록으로 만든다. */
    private static final class FakeProvider implements LlmProvider {
        final List<List<LlmPart>> batchCalls = new ArrayList<>();
        final List<String> singleCalls = new ArrayList<>();
        final Function<List<LlmPart>, LlmReply> batchReply;

        FakeProvider(Function<List<LlmPart>, LlmReply> batchReply) {
            this.batchReply = batchReply;
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText) {
            singleCalls.add(userText);
            return new LlmReply(SINGLE_OK, 100, 10);
        }

        @Override
        public LlmReply call(String model, String systemPrompt, String userText, byte[] jpegImage) {
            return call(model, systemPrompt, userText);
        }

        @Override
        public LlmReply call(String model, String systemPrompt, List<LlmPart> parts) {
            batchCalls.add(parts);
            return batchReply.apply(parts);
        }
    }

    /** 텍스트 조각 수만큼 id 1..n 결과를 PLACE로 돌려준다(skip에 있는 id는 뺀다). */
    private static Function<List<LlmPart>, LlmReply> allPlaceExcept(int... skip) {
        return parts -> {
            List<String> results = new ArrayList<>();
            int n = (int) parts.stream().filter(p -> p.text() != null).count();
            for (int id = 1; id <= n; id++) {
                final int current = id;
                if (java.util.Arrays.stream(skip).noneMatch(s -> s == current)) {
                    results.add("{\"id\":\"" + id + "\",\"category\":\"PLACE\",\"tags\":[\"카페\"],\"summary\":\"s\"}");
                }
            }
            return new LlmReply("{\"results\":[" + String.join(",", results) + "]}", 900, 90);
        };
    }

    private LlmClassifier llm(LlmProvider provider) {
        return new LlmClassifier("m", 0, provider, mapper, PromptVersion.V1, ms -> { }, System::nanoTime);
    }

    private static List<LlmPrompt.BatchItem> texts(int n) {
        List<LlmPrompt.BatchItem> items = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            items.add(new LlmPrompt.BatchItem("텍스트" + i, null));
        }
        return items;
    }

    @Test
    void 순번별로_결과를_매칭하고_호출은_한_번이다() {
        FakeProvider provider = new FakeProvider(allPlaceExcept());

        LlmClassifier.BatchOutcome batch = llm(provider).classifyBatch(texts(3));

        assertThat(provider.batchCalls).hasSize(1);
        assertThat(provider.singleCalls).isEmpty();
        assertThat(batch.outcomes()).extracting(LlmOutcome::status).containsOnly(LlmOutcome.Status.OK);
        assertThat(batch.outcomes().get(0).result().category()).isEqualTo(Category.PLACE);
        assertThat(batch.calls()).hasSize(1);
        assertThat(batch.calls().get(0).items()).isEqualTo(3);
        assertThat(batch.calls().get(0).usage().inputTokens()).isEqualTo(900);
        assertThat(batch.outcomes().get(0).usage().inputTokens()).isEqualTo(300); // 3등분
    }

    @Test
    void 응답에서_빠진_장만_단건으로_다시_보낸다() {
        FakeProvider provider = new FakeProvider(allPlaceExcept(2));

        LlmClassifier.BatchOutcome batch = llm(provider).classifyBatch(texts(3));

        assertThat(provider.singleCalls).hasSize(1);
        assertThat(provider.singleCalls.get(0)).contains("텍스트2");
        assertThat(batch.outcomes().get(1).result().category()).isEqualTo(Category.CHAT); // 단건 결과
        assertThat(batch.outcomes().get(0).result().category()).isEqualTo(Category.PLACE);
        assertThat(batch.calls()).extracting(LlmClassifier.CallUsage::items).containsExactly(3, 1);
    }

    @Test
    void 응답_전체가_JSON이_아니면_전원_단건으로_보낸다() {
        FakeProvider provider = new FakeProvider(parts -> new LlmReply("모르겠어요", 50, 5));

        LlmClassifier.BatchOutcome batch = llm(provider).classifyBatch(texts(3));

        assertThat(provider.singleCalls).hasSize(3);
        assertThat(batch.outcomes()).extracting(LlmOutcome::status).containsOnly(LlmOutcome.Status.OK);
    }

    @Test
    void 호출_자체가_실패하면_단건_재시도_없이_전원_실패() {
        FakeProvider provider = new FakeProvider(parts -> {
            throw HttpClientErrorException.create(HttpStatus.UNAUTHORIZED, "Unauthorized", HttpHeaders.EMPTY,
                    "{}".getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
        });

        LlmClassifier.BatchOutcome batch = llm(provider).classifyBatch(texts(3));

        assertThat(provider.singleCalls).isEmpty();
        assertThat(batch.outcomes()).extracting(LlmOutcome::status).containsOnly(LlmOutcome.Status.CALL_FAILED);
    }

    @Test
    void 한_장이면_배치_프롬프트_없이_단건으로_보낸다() {
        FakeProvider provider = new FakeProvider(allPlaceExcept());

        llm(provider).classifyBatch(texts(1));

        assertThat(provider.batchCalls).isEmpty();
        assertThat(provider.singleCalls).hasSize(1);
    }

    @Test
    void 하이브리드는_텍스트와_이미지를_따로_크기만큼_묶고_입력_순서로_돌려준다() {
        FakeProvider provider = new FakeProvider(allPlaceExcept());
        UsageMeter meter = new UsageMeter();
        HybridLlmClassifier hybrid = new HybridLlmClassifier(llm(provider), 150, 2, 2, meter);
        String longText = "가".repeat(150);
        List<Classifier.Input> inputs = List.of(
                new Classifier.Input(longText, IMAGE),   // 기준값 이상 → 텍스트
                new Classifier.Input("짧음", IMAGE),     // 이미지
                new Classifier.Input(longText, null),    // 텍스트
                new Classifier.Input("짧음2", IMAGE),    // 이미지
                new Classifier.Input(longText, null));   // 텍스트
        assertThat(hybrid.imageDecision("짧음")).isEqualTo(ImageDecision.USE);

        List<Classifier.Classified> results = hybrid.classifyAll(inputs);

        // 텍스트 3장 → 2+1(단건), 이미지 2장 → 1번
        assertThat(provider.batchCalls).hasSize(2);
        assertThat(provider.singleCalls).hasSize(1);
        assertThat(provider.batchCalls.get(0)).allMatch(p -> p.jpegImage() == null);
        assertThat(provider.batchCalls.get(1)).filteredOn(p -> p.jpegImage() != null).hasSize(2);
        assertThat(results).hasSize(5).allMatch(r -> r.error() == null);
        assertThat(results.get(4).result().category()).isEqualTo(Category.CHAT); // 남은 1장은 단건 응답
        assertThat(results.get(1).result()).isEqualTo(new ClassificationResult(Category.PLACE, List.of("카페"), "s"));
        assertThat(meter.snapshot().llmCalls()).isEqualTo(3);
        assertThat(meter.snapshot().llmItems()).isEqualTo(5);
    }
}
