package com.remine.server.controller;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.dto.ConfigResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 민감하지 않은 정책값이라 X-Device-Id 없이 연다. */
@RestController
@RequiredArgsConstructor
public class ConfigController {

    private final RemineProperties properties;

    @GetMapping("/api/config")
    public ConfigResponse config() {
        return ConfigResponse.from(properties);
    }
}
