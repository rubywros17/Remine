package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

/** 서버에 Firebase 키(remine.fcm.credentials-file)가 없어 푸시가 꺼져 있다. */
@ResponseStatus(HttpStatus.SERVICE_UNAVAILABLE)
public class PushDisabledException extends RuntimeException {

    public PushDisabledException() {
        super("서버 푸시가 꺼져 있습니다(remine.fcm.credentials-file).");
    }
}
