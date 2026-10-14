package com.remine.server.domain.screenshot;

/** 목록 조회용: 스크린샷 id와 태그 이름 한 쌍. */
public record ScreenshotTagRow(Long screenshotId, String tagName) {
}
