package com.remine.server.dto;

/** 토큰은 없어도 된다(FCM 토큰을 못 받은 기기도 등록·동기화는 되고, 푸시만 안 간다). */
public record DeviceRegisterRequest(String fcmToken) {
}
