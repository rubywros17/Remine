package com.remine.server.dto;

import java.util.List;

public record ScreenshotPageResponse(
        List<ScreenshotResponse> items,
        int page,
        int size,
        long totalElements,
        int totalPages) {
}
