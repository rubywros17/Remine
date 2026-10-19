package com.remine.server.dto;

import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.CategorySource;
import com.remine.server.domain.screenshot.Screenshot;

/** 수정된 캡처의 요약. autoCategory는 모델이 처음 낸 값(불변), category는 현재 값. */
public record CategoryUpdateResponse(Long id, Category category, Category autoCategory, CategorySource categorySource) {

    public static CategoryUpdateResponse of(Screenshot s) {
        return new CategoryUpdateResponse(s.getId(), s.getCategory(), s.getAutoCategory(), s.getCategorySource());
    }
}
