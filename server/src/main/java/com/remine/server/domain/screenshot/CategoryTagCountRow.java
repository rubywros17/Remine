package com.remine.server.domain.screenshot;

/** 요약용: 카테고리 안에서 태그가 쓰인 횟수. */
public record CategoryTagCountRow(Category category, String tagName, long count) {
}
