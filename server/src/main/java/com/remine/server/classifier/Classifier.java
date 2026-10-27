package com.remine.server.classifier;

import java.util.ArrayList;
import java.util.List;

/**
 * OCR 텍스트(+선택적 이미지) → 카테고리·태그·요약. LLM 구현체로 교체할 수 있도록 분리한 경계.
 * 분류에 실패하면 ETC로 얼버무리지 않고 {@link ClassificationException}을 던진다(호출하는 쪽이 미분석으로 남긴다).
 */
public interface Classifier {

    /**
     * @param jpegImage 분석용으로 줄인 이미지. 없으면 null이고 텍스트만으로 분류한다.
     *                  이미지를 실제로 쓸지(OCR이 짧을 때만)는 구현체가 정한다.
     * @throws ClassificationException 호출 실패나 해석할 수 없는 응답
     */
    ClassificationResult classify(String ocrText, byte[] jpegImage);

    /**
     * 이 OCR 텍스트의 캡처에 이미지가 오면 쓸지. 서비스는 이 값으로 이미지를 검증·축소할지만 정하고,
     * {@link #classify}도 같은 판단을 다시 적용하므로 서비스를 우회해도 쓰면 안 되는 이미지는 나가지 않는다.
     * 기본은 이미지를 쓰지 않는다.
     */
    default ImageDecision imageDecision(String ocrText) {
        return ImageDecision.NOT_SUPPORTED;
    }

    /** 이미지 없이 텍스트만으로 분류한다. */
    default ClassificationResult classify(String ocrText) {
        return classify(ocrText, null);
    }

    /** 분류할 캡처 한 장. jpegImage는 {@link #classify(String, byte[])}와 같다. */
    record Input(String ocrText, byte[] jpegImage) {
    }

    /** 한 장의 결과. 성공이면 result, 실패면 error가 null이 아니다. */
    record Classified(ClassificationResult result, ClassificationException error) {
    }

    /**
     * 여러 장을 분류한다. 결과는 입력 순서와 같고 한 장의 실패가 나머지를 막지 않는다.
     * 기본은 한 장씩 {@link #classify(String, byte[])}이고, LLM 구현체는 여러 장을 한 요청으로 묶는다.
     */
    default List<Classified> classifyAll(List<Input> inputs) {
        List<Classified> results = new ArrayList<>();
        for (Input input : inputs) {
            try {
                results.add(new Classified(classify(input.ocrText(), input.jpegImage()), null));
            } catch (ClassificationException e) {
                results.add(new Classified(null, e));
            }
        }
        return results;
    }
}
