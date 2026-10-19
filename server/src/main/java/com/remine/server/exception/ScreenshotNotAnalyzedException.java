package com.remine.server.exception;

/** 아직 분석되지 않은(분석 실패로 남은) 캡처는 카테고리를 수정할 수 없다. 409로 응답한다. */
public class ScreenshotNotAnalyzedException extends RuntimeException {

    public ScreenshotNotAnalyzedException() {
        super("아직 분석되지 않은 스크린샷입니다. 분석이 끝난 뒤에 수정해 주세요.");
    }
}
