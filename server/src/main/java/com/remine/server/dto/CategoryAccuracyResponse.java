package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;

import java.util.List;

/**
 * 실사용 분류 정확도(spec 8장 F-05). 비율은 분모가 0이면 null이다(0%로 오해하지 않게).
 * accuracyUpperBound = 1 − correctionRate: 안 고친 캡처가 맞는지는 알 수 없어 정확도의 상한이다.
 * reviewedAccuracy = confirmed / (confirmed + corrected): 사용자가 직접 본 캡처만의 정확도(표본이 작을 수 있다).
 */
public record CategoryAccuracyResponse(long analyzed, long corrected, long confirmed, long unreviewed,
                                       Double correctionRate, Double accuracyUpperBound, Double reviewedAccuracy,
                                       List<ByCategory> byAutoCategory, List<Confusion> confusions) {

    /** 모델이 낸 카테고리별. 분석된 캡처가 없는 카테고리도 0으로 포함한다. */
    public record ByCategory(Category category, long analyzed, long corrected, long confirmed) {
    }

    /** 사용자가 고친 쌍(모델 값 → 사용자 값). 건수 내림차순. */
    public record Confusion(Category from, Category to, long count) {
    }
}
