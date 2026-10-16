package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;

/**
 * 분류 한 건의 결과. CALL_FAILED는 모델 품질과 무관한 통신 실패라 정확도 집계에서 뺀다.
 * giveUp은 다시 시도해도 소용없어 재시도 없이 또는 대기를 포기하고 끝낸 실패다
 * (잘못된 키 같은 4xx, 서버가 오래 기다리라고 한 쿼터 소진). 러너가 연속 발생 시 후보를 중단하는 기준이다.
 */
public record LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw, boolean giveUp) {

    public LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw) {
        this(result, usage, status, raw, false);
    }

    public enum Status { OK, PARSE_FAILED, CALL_FAILED }
}
