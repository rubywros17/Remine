package com.remine.server.classifier;

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

    /** 이미지 없이 텍스트만으로 분류한다. */
    default ClassificationResult classify(String ocrText) {
        return classify(ocrText, null);
    }
}
