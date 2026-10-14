package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;

/** 분류 한 건의 결과. CALL_FAILED는 모델 품질과 무관한 통신 실패라 정확도 집계에서 뺀다. */
public record LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw) {

    public enum Status { OK, PARSE_FAILED, CALL_FAILED }
}
