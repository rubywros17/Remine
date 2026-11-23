package com.remine.server.exception;

/**
 * 401 + 본문 code=DEVICE_UNAUTHORIZED (ApiExceptionHandler). 토큰이 없을 때와 틀릴 때를 구분하지 않는다
 * (어느 쪽인지 알려 주면 추측에 단서가 된다). 앱은 이 응답을 받으면 기기를 다시 등록한다.
 */
public class DeviceUnauthorizedException extends RuntimeException {

    public static final String CODE = "DEVICE_UNAUTHORIZED";

    public DeviceUnauthorizedException() {
        super("기기 인증 실패");
    }
}
