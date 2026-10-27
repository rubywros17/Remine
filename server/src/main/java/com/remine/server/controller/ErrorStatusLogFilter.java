package com.remine.server.controller;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * 4xx·5xx 응답을 WARN 한 줄로 남긴다. 검증 실패(400)·미등록 기기(404)·409 등은 스프링이 로그 없이 돌려줘서,
 * 실기기에서 앱이 "서버가 불안정해요"를 띄울 때 서버 쪽에 흔적이 없었다.
 * 남기는 것은 메서드·경로·상태 코드뿐: 쿼리(태그 이름)·헤더(기기 id)·본문(OCR)·예외 메시지는 찍지 않는다.
 */
@Component
public class ErrorStatusLogFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ErrorStatusLogFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            chain.doFilter(request, response);
        } catch (IOException | ServletException | RuntimeException e) {
            // 처리되지 않은 예외: 컨테이너가 500으로 바꾼다. 스프링도 ERROR로 남기지만 같은 형식의 한 줄을 맞춰 둔다.
            log.warn("{} {} → 500 ({})", request.getMethod(), request.getRequestURI(), e.getClass().getSimpleName());
            throw e;
        }
        int status = response.getStatus();
        if (status >= 400) {
            log.warn("{} {} → {}", request.getMethod(), request.getRequestURI(), status);
        }
    }
}
