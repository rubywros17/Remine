package com.remine.server.classifier;

/** 분류기가 이 캡처의 이미지를 쓸지에 대한 판단. USE 외에는 이미지를 쓰지 않는다(사유 코드로 로그/집계). */
public enum ImageDecision {
    /** 이미지를 함께 보낸다. */
    USE,
    /** OCR 글자 수가 기준값 이상이라 텍스트만으로 충분하다. */
    ABOVE_THRESHOLD,
    /** OCR에 전화번호 마스킹 표시가 있다 — 앱 실수로 이미지가 와도 쓰지 않는다. */
    PHONE_MASKED,
    /** 이 분류기는 이미지를 쓰지 않는다. */
    NOT_SUPPORTED
}
