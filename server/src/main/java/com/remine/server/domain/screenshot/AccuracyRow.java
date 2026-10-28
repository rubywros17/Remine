package com.remine.server.domain.screenshot;

/** 정확도 집계용: (모델 값, 현재 값, 출처)별 분석된 캡처 수. */
public record AccuracyRow(Category autoCategory, Category category, CategorySource source, long count) {
}
