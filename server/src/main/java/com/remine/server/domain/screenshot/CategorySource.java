package com.remine.server.domain.screenshot;

/** 현재 category 값의 출처. */
public enum CategorySource {
    /** 모델이 분류한 값 그대로(사용자가 아직 검토하지 않음). */
    AUTO,
    /** 사용자가 직접 지정하거나 확인한 값. 재분석이 덮어쓰지 않는다. */
    USER
}
