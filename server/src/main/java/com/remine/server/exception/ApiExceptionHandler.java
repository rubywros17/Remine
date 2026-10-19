package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
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

    @ExceptionHandler(BatchTooLargeException.class)
    public ProblemDetail batchTooLarge(BatchTooLargeException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        problem.setTitle("요청 항목 수 초과");
        problem.setProperty("requested", e.requested());
        problem.setProperty("max", e.max());
        return problem;
    }
}
