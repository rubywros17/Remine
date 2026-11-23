package com.remine.server.controller;

import com.remine.server.auth.CurrentDevice;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.dto.ConfigResponse;
import com.remine.server.service.OlderQuota;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 민감하지 않은 정책값이라 기기 토큰 없이 연다. 토큰이 맞으면 그 기기의 오늘 남은 예전 스크린샷 몫도 준다
 * (토큰이 없거나 틀려도 401 없이 null — 앱은 기기 등록 전에도 설정을 읽는다).
 */
@RestController
@RequiredArgsConstructor
public class ConfigController {

    private final RemineProperties properties;
    private final OlderQuota olderQuota;

    @GetMapping("/api/config")
    public ConfigResponse config(@CurrentDevice(required = false) Long deviceId) {
        if (deviceId == null) {
            return ConfigResponse.from(properties);
        }
        return ConfigResponse.from(properties, olderQuota.remainingToday(deviceId), olderQuota.resetsAt());
    }
}
