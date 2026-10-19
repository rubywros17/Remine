package com.remine.server.exception;

import com.remine.server.domain.screenshot.Category;

import java.util.Arrays;
import java.util.List;

/** 요청한 카테고리가 없거나 7개 기본 카테고리에 없다. 400으로 응답하며 허용 값 목록을 함께 준다. */
public class CategoryNotAllowedException extends RuntimeException {

    private static final List<String> ALLOWED = Arrays.stream(Category.values()).map(Enum::name).toList();

    public CategoryNotAllowedException() {
        super("category는 다음 중 하나여야 합니다: " + String.join(", ", ALLOWED));
    }

    public List<String> allowed() {
        return ALLOWED;
    }
}
