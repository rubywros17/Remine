package com.remine.server.image;

/**
 * 분석에 쓸 수 없는 이미지. 메시지와 원인에는 이미지 바이트·ImageIO 예외 내용을 담지 않고 고정 문구와 사유 코드만 둔다
 * (이미지는 로그나 예외 어디에도 남기지 않는다).
 */
public class InvalidImageException extends RuntimeException {

    public enum Reason {
        /** 매직 바이트(FF D8 FF)가 JPEG가 아니다. */
        NOT_JPEG,
        /** JPEG 형식이지만 디코딩할 수 없다(손상, 지원하지 않는 변형). */
        UNREADABLE,
        /** 픽셀 수가 상한을 넘는다(압축폭탄 방어, 디코딩 전에 헤더로 판단). */
        TOO_MANY_PIXELS
    }

    private final Reason reason;

    public InvalidImageException(Reason reason) {
        super("분석에 쓸 수 없는 이미지입니다 (" + reason + ")");
        this.reason = reason;
    }

    public Reason reason() {
        return reason;
    }
}
