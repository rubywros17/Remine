package com.remine.server.classifier;

/**
 * 분류를 끝내지 못했다. 메시지에는 OCR 원문·이미지·키·제공사 응답 본문을 담지 않는다(상태 코드 수준 요약만).
 */
public class ClassificationException extends RuntimeException {

    public enum Reason {
        /** 호출 자체가 실패했다(통신 오류, 4xx/5xx, 쿼터 소진). */
        CALL_FAILED,
        /** 응답을 받았지만 카테고리·JSON을 해석할 수 없다. */
        INVALID_RESPONSE,
        /** 요청 마감이 지나 호출을 시작하지 않았다. */
        DEADLINE_EXCEEDED
    }

    public static ClassificationException deadlineExceeded() {
        return new ClassificationException(Reason.DEADLINE_EXCEEDED, "요청 마감이 지나 호출하지 않음");
    }

    private final Reason reason;

    public ClassificationException(Reason reason, String safeSummary) {
        super(safeSummary);
        this.reason = reason;
    }

    public Reason reason() {
        return reason;
    }
}
