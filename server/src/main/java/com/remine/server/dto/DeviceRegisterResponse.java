package com.remine.server.dto;

/**
 * 기기 인증 토큰 원문. 이 응답으로 한 번만 나가고 서버에는 해시만 남는다(다시 받을 방법이 없다).
 * 숫자 기기 id는 서버 내부 값이라 내보내지 않는다.
 */
public record DeviceRegisterResponse(String token) {
}
