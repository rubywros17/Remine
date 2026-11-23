package com.remine.server.controller;

import com.remine.server.auth.CurrentDevice;
import com.remine.server.dto.CategoryAccuracyResponse;
import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.service.ScreenshotQueryService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/categories")
@RequiredArgsConstructor
public class CategoryController {

    private final ScreenshotQueryService screenshotQueryService;

    @GetMapping("/summary")
    public CategorySummaryResponse summary(@CurrentDevice Long deviceId) {
        return screenshotQueryService.summary(deviceId);
    }

    @GetMapping("/accuracy")
    public CategoryAccuracyResponse accuracy(@CurrentDevice Long deviceId) {
        return screenshotQueryService.accuracy(deviceId);
    }
}
