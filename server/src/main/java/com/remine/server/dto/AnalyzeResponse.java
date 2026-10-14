package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/** analyzed: 이번에 분석한 결과, skipped: 이미 분석돼 있어 건너뛴 localAssetId. */
public record AnalyzeResponse(List<Result> analyzed, List<String> skipped) {

    public record Result(String localAssetId, Category category, List<String> tags, String summary) {
    }
}
