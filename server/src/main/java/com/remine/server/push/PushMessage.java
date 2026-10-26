package com.remine.server.push;

import java.util.Map;

/** 기기 한 대에 보낼 알림. data는 앱이 알림을 눌렀을 때 열 화면을 정하는 데만 쓴다(OCR 원문·요약을 담지 않는다). */
public record PushMessage(String title, String body, Map<String, String> data) {
}
