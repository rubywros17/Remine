package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

/** 이 기기는 알림을 끄고 있다(서버에 FCM 토큰이 없다). */
@ResponseStatus(HttpStatus.CONFLICT)
public class NoFcmTokenException extends RuntimeException {

    public NoFcmTokenException() {
        super("이 기기에는 알림 토큰이 없습니다. 앱 설정에서 알림을 켜 주세요.");
    }
}
