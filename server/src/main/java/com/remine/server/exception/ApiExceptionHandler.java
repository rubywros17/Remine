package com.remine.server.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 오류 본문에 사람이 읽을 수 있는 메시지가 필요한 예외만 처리한다.
 * (스프링 기본 설정은 오류 응답에 message를 싣지 않는다.)
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(BatchTooLargeException.class)
    public ProblemDetail batchTooLarge(BatchTooLargeException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        problem.setTitle("요청 항목 수 초과");
        problem.setProperty("requested", e.requested());
        problem.setProperty("max", e.max());
        return problem;
    }
}
