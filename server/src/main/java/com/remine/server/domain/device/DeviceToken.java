package com.remine.server.domain.device;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * 기기 인증 토큰: 256비트 무작위 값(URL-safe Base64, 패딩 없음 43자).
 * 서버는 원문을 저장하지 않고 {@link #hash} 결과만 저장·비교한다. 원문은 등록 응답으로 한 번만 나간다.
 */
public final class DeviceToken {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();

    private DeviceToken() {
    }

    public static String generate() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return ENCODER.encodeToString(bytes);
    }

    /** SHA-256. 토큰이 256비트 무작위라 솔트·느린 해시(bcrypt 등)는 필요 없다(사전 공격 대상이 아니다). */
    public static byte[] hash(String token) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.US_ASCII));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256은 모든 JVM에 있다", e);
        }
    }
}
