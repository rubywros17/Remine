package com.remine.server.exception;

/**
 * analyze 요청의 구조 오류(JSON 오류, request 파트 누락, 짝이 없는 이미지 파트 등). 400으로 응답한다.
 * 메시지는 고정 문구와 필드 경로만 담는다 — 요청 본문(OCR 원문)이나 이미지 내용을 되풀이하지 않는다.
 */
public class InvalidAnalyzeRequestException extends RuntimeException {

    public InvalidAnalyzeRequestException(String message) {
        super(message);
    }
}
