package com.remine.server.exception;

/** 없는 id이거나 다른 기기의 캡처. 둘을 구분할 수 없게 같은 예외·같은 본문(404)으로 응답한다. */
public class ScreenshotNotFoundException extends RuntimeException {

    public ScreenshotNotFoundException() {
        super("스크린샷을 찾을 수 없습니다.");
    }
}
