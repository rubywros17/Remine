package com.remine.server.auth;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 컨트롤러 파라미터({@code Long deviceId})에 붙이면 {@code Authorization: Bearer <기기 토큰>}으로 찾은 기기 id가 들어온다.
 * 숫자 id는 서버 안에서만 쓰고 요청·응답·로그에 내보내지 않는다.
 * {@code required=false}면 토큰이 없거나 틀려도 401 없이 null(GET /api/config처럼 기기 없이도 여는 API).
 */
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface CurrentDevice {
    boolean required() default true;
}
