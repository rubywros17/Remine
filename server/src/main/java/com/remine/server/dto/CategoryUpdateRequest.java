package com.remine.server.dto;

/** 문자열로 받아 서비스에서 Category로 변환한다(잘못된 값에 허용 값 목록을 돌려주기 위해). */
public record CategoryUpdateRequest(String category) {
}
