package com.remine.server.controller;

import com.remine.server.dto.InterestResponse;
import com.remine.server.service.InterestService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/interests")
@RequiredArgsConstructor
public class InterestController {

    private final InterestService interestService;

    @GetMapping
    public InterestResponse list(@RequestHeader("X-Device-Id") Long deviceId) {
        return interestService.list(deviceId);
    }
}
