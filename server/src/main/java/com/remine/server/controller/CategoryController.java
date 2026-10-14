package com.remine.server.controller;

import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.service.ScreenshotQueryService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/categories")
@RequiredArgsConstructor
public class CategoryController {

    private final ScreenshotQueryService screenshotQueryService;

    @GetMapping("/summary")
    public CategorySummaryResponse summary(@RequestHeader("X-Device-Id") Long deviceId) {
        return screenshotQueryService.summary(deviceId);
    }
}
