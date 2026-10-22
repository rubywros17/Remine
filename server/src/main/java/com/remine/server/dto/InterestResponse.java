package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/**
 * GET /api/interests. 관심사가 없으면 빈 items.
 * OCR 원문·요약은 담지 않는다. recent의 localAssetId는 앱이 기기 사진으로 썸네일을 그리는 데 쓴다.
 */
public record InterestResponse(List<Item> items) {

    /**
     * @param spanDays    집계 기간(일). 카드 문구 "2주 동안"의 근거
     * @param dormantDays 마지막 캡처 이후 지난 일수(오늘이면 0)
     * @param recent      최근 캡처 최대 3개, 최신순
     */
    public record Item(String tag, Category category, int captureCount, int spanDays, long dormantDays,
                       List<Capture> recent) {
    }

    public record Capture(Long id, String localAssetId) {
    }
}
