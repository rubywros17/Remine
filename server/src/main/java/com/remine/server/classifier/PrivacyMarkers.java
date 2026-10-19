package com.remine.server.classifier;

/** 앱과 서버가 약속한 개인정보 마스킹 표시. 표시 문자열은 이 상수 한 곳에서만 정의한다. */
public final class PrivacyMarkers {

    /** 앱이 전화번호를 가린 자리에 넣는 표시. 이 표시가 있는 캡처의 이미지는 서버가 분류에 쓰지 않는다. */
    public static final String PHONE_NUMBER_MASK = "[전화번호]";

    private PrivacyMarkers() {
    }
}
