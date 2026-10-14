package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;

import java.time.LocalDateTime;
import java.util.List;

public record ScreenshotResponse(
        Long id,
        String localAssetId,
        LocalDateTime takenAt,
        String sourceApp,
        Category category,
        String summary,
        List<String> tags) {

    public static ScreenshotResponse of(Screenshot s, List<String> tags) {
        return new ScreenshotResponse(s.getId(), s.getLocalAssetId(), s.getTakenAt(),
                s.getSourceApp(), s.getCategory(), s.getSummary(), tags);
    }
}
