package com.remine.server.controller;

import com.remine.server.classifier.UsageMeter;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 개발용: Key Numbers 측정값(요청 수·LLM 호출 수·토큰·비용·처리 시간). 측정 전에 DELETE로 0으로 만들고 끝나면 GET.
 * dev 프로필에서만 빈이 생긴다 → 기본 실행에서는 404. 기기 구분 없는 서버 전체 합계다(측정은 기기 1대로 한다).
 */
@Profile("dev")
@RestController
@RequestMapping("/api/dev/metrics")
@RequiredArgsConstructor
public class DevMetricsController {

    private final UsageMeter meter;

    @GetMapping
    public UsageMeter.Snapshot get() {
        return meter.snapshot();
    }

    @DeleteMapping
    public ResponseEntity<Void> reset() {
        meter.reset();
        return ResponseEntity.noContent().build();
    }
}
