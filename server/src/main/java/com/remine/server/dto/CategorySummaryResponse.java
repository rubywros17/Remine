package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/** 홈 화면용. 스크린샷이 없는 카테고리도 count 0, 빈 배열로 포함한다. */
public record CategorySummaryResponse(List<Item> categories) {

    public record Item(Category category, long count, List<String> topTags, List<String> recentAssetIds) {
    }
}
