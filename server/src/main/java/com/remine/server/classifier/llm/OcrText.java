package com.remine.server.classifier.llm;

/** OCR 텍스트 관련 공용 계산. 운영 하이브리드 분류와 실험 통계가 같은 기준을 쓴다. */
public final class OcrText {

    private OcrText() {
    }

    /** 공백(줄바꿈 포함)을 뺀 글자 수. null이면 0. 하이브리드 기준값(이미지를 쓸지)과 실험의 글자 수 구간이 이 값을 쓴다. */
    public static int countChars(String ocrText) {
        if (ocrText == null) {
            return 0;
        }
        return (int) ocrText.codePoints().filter(cp -> !Character.isWhitespace(cp)).count();
    }
}
