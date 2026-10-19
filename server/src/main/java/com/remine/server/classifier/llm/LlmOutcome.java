package com.remine.server.classifier.llm;

import com.remine.server.classifier.ClassificationResult;

/**
 * 분류 한 건의 결과. CALL_FAILED는 모델 품질과 무관한 통신 실패라 정확도 집계에서 뺀다.
 * giveUp은 다시 시도해도 소용없어 재시도 없이 또는 대기를 포기하고 끝낸 실패다
 * (잘못된 키 같은 4xx, 서버가 오래 기다리라고 한 쿼터 소진). 러너가 연속 발생 시 후보를 중단하는 기준이다.
 * summary는 로그·응답에 써도 안전한 실패 요약(상태 코드 수준)이다. raw는 모델 원문·제공사 응답 본문을 담을 수 있어 운영 로그에 쓰지 않는다.
 */
public record LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw, boolean giveUp,
                         String summary) {

    public LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw) {
        this(result, usage, status, raw, false, "");
    }

    public LlmOutcome(ClassificationResult result, LlmUsage usage, Status status, String raw, boolean giveUp) {
        this(result, usage, status, raw, giveUp, "");
    }

    public enum Status { OK, PARSE_FAILED, CALL_FAILED }
}
