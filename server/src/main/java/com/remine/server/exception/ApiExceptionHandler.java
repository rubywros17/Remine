package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.MultipartException;

/**
 * 오류 본문에 사람이 읽을 수 있는 메시지가 필요한 예외만 처리한다.
 * (스프링 기본 설정은 오류 응답에 message를 싣지 않는다.)
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    /**
     * JSON 본문을 읽을 수 없다(문법 오류, 타입·값 불일치). 예외 메시지에는 잘못된 값(OCR 원문 등)이 섞일 수 있어
     * 응답에 쓰지 않고 고정 문구만 돌려준다.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ProblemDetail unreadableBody() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                "요청 본문을 읽을 수 없습니다. JSON 형식과 필드 타입을 확인해 주세요.");
        problem.setTitle("잘못된 요청 본문");
        return problem;
    }

    @ExceptionHandler(InvalidAnalyzeRequestException.class)
    public ProblemDetail invalidAnalyzeRequest(InvalidAnalyzeRequestException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        problem.setTitle("잘못된 analyze 요청");
        return problem;
    }

    /** 컨테이너 하드 상한(파트·요청 전체) 초과. 부분 처리 없이 요청 전체를 거절한다. */
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ProblemDetail uploadTooLarge() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONTENT_TOO_LARGE,
                "요청이 너무 큽니다. 이미지를 더 줄이거나 장수를 나누어 보내 주세요 (GET /api/config의 maxRequestBytes 참고).");
        problem.setTitle("요청 크기 초과");
        return problem;
    }

    /** 그 밖의 multipart 해석 오류. 예외 메시지(요청 내용이 섞일 수 있음)는 응답에 쓰지 않는다. */
    @ExceptionHandler(MultipartException.class)
    public ProblemDetail malformedMultipart() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                "multipart 요청을 읽을 수 없습니다. 파트 수와 형식을 확인해 주세요.");
        problem.setTitle("잘못된 multipart 요청");
        return problem;
    }

    @ExceptionHandler(CategoryNotAllowedException.class)
    public ProblemDetail categoryNotAllowed(CategoryNotAllowedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        problem.setTitle("허용되지 않는 카테고리");
        problem.setProperty("allowed", e.allowed());
        return problem;
    }

    /**
     * 미등록 기기. 앱은 code로 "서버가 이 기기를 잊었다(DB 초기화 등)"를 다른 404(없는 캡처·없는 경로)와 구분해
     * 재등록한다. 메시지에 기기 id를 싣지 않는다.
     */
    @ExceptionHandler(DeviceNotFoundException.class)
    public ProblemDetail deviceNotFound() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND,
                "등록되지 않은 기기입니다. 기기를 다시 등록해 주세요.");
        problem.setTitle("미등록 기기");
        problem.setProperty("code", DeviceNotFoundException.CODE);
        return problem;
    }

    @ExceptionHandler(ScreenshotNotFoundException.class)
    public ProblemDetail screenshotNotFound(ScreenshotNotFoundException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        problem.setTitle("스크린샷 없음");
        return problem;
    }

    @ExceptionHandler(ScreenshotNotAnalyzedException.class)
    public ProblemDetail screenshotNotAnalyzed(ScreenshotNotAnalyzedException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
        problem.setTitle("분석되지 않은 스크린샷");
        return problem;
    }

    @ExceptionHandler(BatchTooLargeException.class)
    public ProblemDetail batchTooLarge(BatchTooLargeException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        problem.setTitle("요청 항목 수 초과");
        problem.setProperty("requested", e.requested());
        problem.setProperty("max", e.max());
        return problem;
    }
}
