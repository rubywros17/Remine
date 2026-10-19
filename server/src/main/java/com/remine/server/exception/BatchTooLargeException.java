package com.remine.server.exception;

/** analyze 요청 하나에 담을 수 있는 최대 캡처 수(remine.analyze.max-batch-size)를 넘었다. 400으로 응답한다. */
public class BatchTooLargeException extends RuntimeException {

    private final int requested;
    private final int max;

    public BatchTooLargeException(int requested, int max) {
        super("한 번에 최대 " + max + "장까지 분석할 수 있습니다 (요청 " + requested + "장). "
                + max + "장 이하로 나누어 보내 주세요.");
        this.requested = requested;
        this.max = max;
    }

    public int requested() {
        return requested;
    }

    public int max() {
        return max;
    }
}
