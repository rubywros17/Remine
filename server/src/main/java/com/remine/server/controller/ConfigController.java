package com.remine.server.controller;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.dto.ConfigResponse;
import com.remine.server.service.OlderQuota;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * 민감하지 않은 정책값이라 X-Device-Id 없이 연다. 헤더가 있고 등록된 기기면 그 기기의 오늘 남은 예전 스크린샷 몫도 준다
 * (모르는 기기여도 404 없이 null — 앱은 기기 등록 전에도 설정을 읽는다).
 */
@RestController
@RequiredArgsConstructor
public class ConfigController {

    private final RemineProperties properties;
    private final DeviceRepository deviceRepository;
    private final OlderQuota olderQuota;

    @GetMapping("/api/config")
    public ConfigResponse config(@RequestHeader(value = "X-Device-Id", required = false) Long deviceId) {
        if (deviceId == null || !deviceRepository.existsById(deviceId)) {
            return ConfigResponse.from(properties);
        }
        return ConfigResponse.from(properties, olderQuota.remainingToday(deviceId), olderQuota.resetsAt());
    }
}
