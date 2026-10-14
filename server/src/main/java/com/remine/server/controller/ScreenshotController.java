package com.remine.server.controller;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.service.ScreenshotQueryService;
import com.remine.server.service.ScreenshotService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/screenshots")
@RequiredArgsConstructor
public class ScreenshotController {

    private final ScreenshotService screenshotService;
    private final ScreenshotQueryService screenshotQueryService;

    @PostMapping("/analyze")
    public AnalyzeResponse analyze(@RequestHeader("X-Device-Id") Long deviceId,
                                   @Valid @RequestBody AnalyzeRequest request) {
        return screenshotService.analyze(deviceId, request);
    }

    @GetMapping
    public ScreenshotPageResponse list(@RequestHeader("X-Device-Id") Long deviceId,
                                       @RequestParam(required = false) Category category,
                                       @RequestParam(required = false) String tag,
                                       @RequestParam(defaultValue = "0") @Min(0) int page,
                                       @RequestParam(defaultValue = "30") @Min(1) @Max(100) int size) {
        return screenshotQueryService.list(deviceId, category, tag, page, size);
    }
}
