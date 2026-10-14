package com.remine.server.domain.screenshot;

/** 요약용: 카테고리별 스크린샷 수. */
public record CategoryCountRow(Category category, long count) {
}
