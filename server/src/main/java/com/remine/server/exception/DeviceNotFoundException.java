package com.remine.server.exception;

/** 404 + 본문 code=DEVICE_NOT_FOUND (ApiExceptionHandler). */
public class DeviceNotFoundException extends RuntimeException {

    public static final String CODE = "DEVICE_NOT_FOUND";

    public DeviceNotFoundException(Long deviceId) {
        super("등록되지 않은 기기입니다"); // 기기 id는 메시지에 싣지 않는다(로그로 새지 않게)
    }
}
