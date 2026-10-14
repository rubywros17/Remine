package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(HttpStatus.NOT_FOUND)
public class DeviceNotFoundException extends RuntimeException {

    public DeviceNotFoundException(Long deviceId) {
        super("등록되지 않은 기기입니다: " + deviceId);
    }
}
