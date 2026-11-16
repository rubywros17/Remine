package com.remine.server.dto;

import com.remine.server.domain.interest.InterestStatus;
import com.remine.server.domain.screenshot.Category;

import java.time.LocalDateTime;
import java.util.List;

/**
 * GET /api/interests. 관심사가 없으면 빈 items. 순서: FORGOTTEN(장수↓ → 오래 안 본 순) → RECENT(장수↓).
 * OCR 원문·요약은 담지 않는다. recent의 localAssetId는 앱이 기기 사진으로 썸네일을 그리는 데 쓴다.
 *
 * @param windowDays 옛 앱 호환용(옛 앱은 이 값이 없으면 관심사 목록을 비운다). 값은 recentDays와 같고 새 앱은 읽지 않는다
 * @param recentDays 상태 경계(일). 앱이 휴지통 캡처를 빼고 상태를 다시 판단할 때 쓴다
 * @param minCount   관심사 기준 횟수(전체 기간). 앱이 휴지통 캡처를 빼고 다시 판단할 때 쓴다(서버 설정이 단일 출처)
 */
public record InterestResponse(@Deprecated int windowDays, int recentDays, int minCount, List<Item> items) {

    public InterestResponse(int recentDays, int minCount, List<Item> items) {
        this(recentDays, recentDays, minCount, items);
    }

    /**
     * @param captureCount     전체 기간 장수
     * @param dormantDays      마지막 캡처 이후 지난 일수(오늘이면 0)
     * @param peakMonth        캡처가 가장 많았던 달(1~12, 동점이면 최근 달). 문구 "9월에 12번이나"
     * @param peakMonthCount   그 달의 장수
     * @param latestMonth      마지막 캡처의 달(1~12)
     * @param latestMonthCount 그 달의 장수. 요즘 관심사 문구 "11월에 5번이나"
     * @param recent           최근 캡처 최대 3개, 최신순
     * @param linkedTags       같은 캡처에 함께 붙은 다른 관심사 태그. 앱의 머릿속 지도 연결선
     */
    public record Item(String tag, Category category, InterestStatus status, int captureCount, long dormantDays,
                       int peakMonth, int peakMonthCount, int latestMonth, int latestMonthCount,
                       List<Capture> recent, List<String> linkedTags) {
    }

    /** takenAt은 앱이 휴지통 캡처를 뺀 뒤 마지막 캡처 날짜를 다시 셀 때 쓴다. */
    public record Capture(Long id, String localAssetId, LocalDateTime takenAt) {
    }
}
