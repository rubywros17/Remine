package com.remine.server.domain.screenshot;

import java.time.LocalDateTime;

/** 관심사 감지용: 기간 안 캡처 하나에 붙은 태그 하나. category는 현재 값(사용자 수정 반영). */
public record InterestRow(Long tagId, String tagName, Long screenshotId, String localAssetId,
                          Category category, LocalDateTime takenAt) {
}
