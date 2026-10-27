package com.remine.server.controller;

import com.remine.server.push.PushSender;
import com.remine.server.service.InterestPushService;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 개발용: 이 기기에 관심사 알림 1건을 바로 보낸다(실기기에서 알림·탭 동작 확인).
 * dev 프로필에서만 빈이 생긴다 → 기본 실행에서는 경로 자체가 없어 404.
 * 주간 알림 상태(interest_alert)는 건드리지 않는다.
 *
 * {@code delaySeconds}만큼 서버가 기다렸다 보낸다. 앱은 요청을 곧바로 보내고 내려가면 된다
 * (앱이 기다렸다 보내면, 내려간 앱을 안드로이드가 멈춰 요청이 아예 안 나갈 수 있다).
 */
@Profile("dev")
@RestController
@RequestMapping("/api/dev")
@RequiredArgsConstructor
public class DevPushController {

    private final InterestPushService pushService;

    @PostMapping("/push-test")
    public Map<String, PushSender.Result> pushTest(@RequestHeader("X-Device-Id") Long deviceId,
                                                   @RequestParam(defaultValue = "0") @Min(0) @Max(10) int delaySeconds)
            throws InterruptedException {
        // ponytail: 요청 스레드를 재운다(dev 전용·1건이라 충분). 운영 기능이 되면 스케줄러로.
        Thread.sleep(delaySeconds * 1000L);
        return Map.of("result", pushService.sendTest(deviceId));
    }
}
