package com.remine.server.controller;

import com.remine.server.push.PushSender;
import com.remine.server.service.InterestPushService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 개발용: 이 기기에 관심사 알림 1건을 바로 보낸다(실기기에서 알림·탭 동작 확인).
 * dev 프로필에서만 빈이 생긴다 → 기본 실행에서는 경로 자체가 없어 404.
 * 주간 알림 상태(interest_alert)는 건드리지 않는다.
 */
@Profile("dev")
@RestController
@RequestMapping("/api/dev")
@RequiredArgsConstructor
public class DevPushController {

    private final InterestPushService pushService;

    @PostMapping("/push-test")
    public Map<String, PushSender.Result> pushTest(@RequestHeader("X-Device-Id") Long deviceId) {
        return Map.of("result", pushService.sendTest(deviceId));
    }
}
