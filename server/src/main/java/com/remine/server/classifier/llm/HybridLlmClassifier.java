package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 운영 분류기: OCR 텍스트가 충분하면 텍스트만, 짧으면(기준값 미만) 이미지가 있을 때 이미지도 함께 보낸다.
 * 실험(43장)에서 정한 하이브리드이며 기준값(공백 제외 글자 수, 기본 150)은 설정이다.
 * 이미지가 없으면(null) 글자 수와 무관하게 텍스트만 보낸다. 프롬프트는 v1 고정이다.
 *
 * <p>로그에는 상태·건수·소요 시간·토큰 수만 남긴다. OCR 원문·이미지·키·제공사 응답 본문은 남기지 않는다.
 */
public class HybridLlmClassifier implements Classifier {

    private static final Logger log = LoggerFactory.getLogger(HybridLlmClassifier.class);

    private final LlmClassifier llm;
    private final int imageThresholdChars;

    public HybridLlmClassifier(LlmClassifier llm, int imageThresholdChars) {
        this.llm = llm;
        this.imageThresholdChars = imageThresholdChars;
    }

    public int imageThresholdChars() {
        return imageThresholdChars;
    }

    public String model() {
        return llm.model();
    }

    @Override
    public ClassificationResult classify(String ocrText, byte[] jpegImage) {
        boolean useImage = jpegImage != null && jpegImage.length > 0
                && OcrText.countChars(ocrText) < imageThresholdChars;

        LlmOutcome outcome = llm.classifyWithUsage(ocrText, useImage ? jpegImage : null);

        log.info("분류 status={} image={} tokens={}/{} latencyMs={}", outcome.status(), useImage,
                outcome.usage().inputTokens(), outcome.usage().outputTokens(), outcome.usage().latencyMs());
        if (outcome.status() == LlmOutcome.Status.OK) {
            return outcome.result();
        }
        log.warn("분류 실패 status={} image={} summary={}", outcome.status(), useImage, outcome.summary());
        throw new ClassificationException(
                outcome.status() == LlmOutcome.Status.PARSE_FAILED
                        ? ClassificationException.Reason.INVALID_RESPONSE
                        : ClassificationException.Reason.CALL_FAILED,
                outcome.summary());
    }
}
