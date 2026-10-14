package com.remine.server.classifier;

/** OCR 텍스트 → 카테고리·태그·요약. LLM 구현체로 교체할 수 있도록 분리한 경계. */
public interface Classifier {

    ClassificationResult classify(String ocrText);
}
