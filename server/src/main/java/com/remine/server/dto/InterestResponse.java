package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/**
 * GET /api/interests. 관심사가 없으면 빈 items.
 * OCR 원문·요약은 담지 않는다. recent의 localAssetId는 앱이 기기 사진으로 썸네일을 그리는 데 쓴다.
 *
 * @param windowDays 집계 기간(일). 카드 문구 "2주 동안"과 빈 화면 안내의 근거
 * @param minCount   관심사 기준 횟수. 앱이 휴지통 캡처를 빼고 다시 판단할 때 쓴다(서버 설정이 단일 출처)
 */
public record InterestResponse(int windowDays, int minCount, List<Item> items) {

    /**
     * @param dormantDays 마지막 캡처 이후 지난 일수(오늘이면 0)
     * @param recent      최근 캡처 최대 3개, 최신순
     */
    public record Item(String tag, Category category, int captureCount, long dormantDays, List<Capture> recent) {
    }

    public record Capture(Long id, String localAssetId) {
    }
}
