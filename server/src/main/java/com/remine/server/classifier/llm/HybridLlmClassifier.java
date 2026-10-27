package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.ImageDecision;
import com.remine.server.classifier.PrivacyMarkers;
import com.remine.server.classifier.UsageMeter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * 운영 분류기: OCR 텍스트가 충분하면 텍스트만, 짧으면(기준값 미만) 이미지가 있을 때 이미지도 함께 보낸다.
 * 실험(43장)에서 정한 하이브리드이며 기준값(공백 제외 글자 수, 기본 150)은 설정이다.
 * 이미지가 없으면(null) 글자 수와 무관하게 텍스트만 보낸다. 프롬프트는 v1 고정이다.
 *
 * 여러 장은 텍스트만/이미지 포함으로 나눠 설정한 크기씩 한 요청에 묶는다({@link #classifyAll}).
 *
 * <p>로그에는 상태·건수·소요 시간·토큰 수만 남긴다. OCR 원문·이미지·키·제공사 응답 본문은 남기지 않는다.
 */
public class HybridLlmClassifier implements Classifier {

    private static final Logger log = LoggerFactory.getLogger(HybridLlmClassifier.class);

    private final LlmClassifier llm;
    private final int imageThresholdChars;
    private final int textBatchSize;
    private final int imageBatchSize;
    private final UsageMeter meter;

    /** 배치 없이(장당 1요청). 테스트용. */
    public HybridLlmClassifier(LlmClassifier llm, int imageThresholdChars) {
        this(llm, imageThresholdChars, 1, 1, new UsageMeter());
    }

    public HybridLlmClassifier(LlmClassifier llm, int imageThresholdChars, int textBatchSize, int imageBatchSize,
                               UsageMeter meter) {
        this.llm = llm;
        this.imageThresholdChars = imageThresholdChars;
        this.textBatchSize = textBatchSize;
        this.imageBatchSize = imageBatchSize;
        this.meter = meter;
    }

    public int imageThresholdChars() {
        return imageThresholdChars;
    }

    public String model() {
        return llm.model();
    }

    /** 마스킹 표시가 글자 수 조건보다 우선한다. */
    @Override
    public ImageDecision imageDecision(String ocrText) {
        if (ocrText != null && ocrText.contains(PrivacyMarkers.PHONE_NUMBER_MASK)) {
            return ImageDecision.PHONE_MASKED;
        }
        return OcrText.countChars(ocrText) >= imageThresholdChars ? ImageDecision.ABOVE_THRESHOLD : ImageDecision.USE;
    }

    @Override
    public ClassificationResult classify(String ocrText, byte[] jpegImage) {
        boolean hasImage = jpegImage != null && jpegImage.length > 0;
        ImageDecision decision = imageDecision(ocrText);
        boolean useImage = hasImage && decision == ImageDecision.USE;
        if (hasImage && !useImage) {
            log.info("이미지 무시 reason={}", decision);
        }

        LlmOutcome outcome = llm.classifyWithUsage(ocrText, useImage ? jpegImage : null);
        meter.recordCall(1, outcome.usage());

        log.info("분류 status={} image={} tokens={}/{} latencyMs={}", outcome.status(), useImage,
                outcome.usage().inputTokens(), outcome.usage().outputTokens(), outcome.usage().latencyMs());
        if (outcome.status() == LlmOutcome.Status.OK) {
            return outcome.result();
        }
        log.warn("분류 실패 status={} image={} summary={}", outcome.status(), useImage, outcome.summary());
        throw toException(outcome);
    }

    /**
     * 이미지를 쓸 장과 텍스트만 보낼 장을 나눠, 각각 textBatchSize / imageBatchSize장씩 한 요청으로 보낸다.
     * 이미지 사용 판단은 {@link #classify}와 같다(마스킹·기준값 이상이면 이미지를 버린다).
     */
    @Override
    public List<Classified> classifyAll(List<Input> inputs) {
        List<Integer> textIdx = new ArrayList<>();
        List<Integer> imageIdx = new ArrayList<>();
        for (int i = 0; i < inputs.size(); i++) {
            Input input = inputs.get(i);
            boolean hasImage = input.jpegImage() != null && input.jpegImage().length > 0;
            (hasImage && imageDecision(input.ocrText()) == ImageDecision.USE ? imageIdx : textIdx).add(i);
        }
        Classified[] results = new Classified[inputs.size()];
        runBatches(inputs, textIdx, textBatchSize, false, results);
        runBatches(inputs, imageIdx, imageBatchSize, true, results);
        return Arrays.asList(results);
    }

    private void runBatches(List<Input> inputs, List<Integer> indexes, int size, boolean useImage,
                            Classified[] results) {
        for (int from = 0; from < indexes.size(); from += size) {
            List<Integer> chunk = indexes.subList(from, Math.min(from + size, indexes.size()));
            List<LlmPrompt.BatchItem> items = chunk.stream()
                    .map(i -> new LlmPrompt.BatchItem(inputs.get(i).ocrText(), useImage ? inputs.get(i).jpegImage() : null))
                    .toList();
            LlmClassifier.BatchOutcome batch = llm.classifyBatch(items);
            batch.calls().forEach(call -> meter.recordCall(call.items(), call.usage()));

            int failed = 0;
            for (int k = 0; k < chunk.size(); k++) {
                LlmOutcome outcome = batch.outcomes().get(k);
                if (outcome.status() == LlmOutcome.Status.OK) {
                    results[chunk.get(k)] = new Classified(outcome.result(), null);
                } else {
                    failed++;
                    results[chunk.get(k)] = new Classified(null, toException(outcome));
                }
            }
            LlmUsage first = batch.calls().get(0).usage();
            log.info("배치 분류 items={} image={} calls={} failed={} tokens={}/{} latencyMs={}", chunk.size(), useImage,
                    batch.calls().size(), failed, first.inputTokens(), first.outputTokens(), first.latencyMs());
        }
    }

    private static ClassificationException toException(LlmOutcome outcome) {
        return new ClassificationException(
                outcome.status() == LlmOutcome.Status.PARSE_FAILED
                        ? ClassificationException.Reason.INVALID_RESPONSE
                        : ClassificationException.Reason.CALL_FAILED,
                outcome.summary());
    }
}
