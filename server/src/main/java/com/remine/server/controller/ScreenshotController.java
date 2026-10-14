package com.remine.server.controller;

import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.service.ScreenshotService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/screenshots")
@RequiredArgsConstructor
public class ScreenshotController {

    private final ScreenshotService screenshotService;

    @PostMapping("/analyze")
    public AnalyzeResponse analyze(@RequestHeader("X-Device-Id") Long deviceId,
                                   @Valid @RequestBody AnalyzeRequest request) {
        return screenshotService.analyze(deviceId, request);
    }
}
