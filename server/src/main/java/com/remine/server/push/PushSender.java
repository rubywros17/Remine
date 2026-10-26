package com.remine.server.push;

/**
 * 푸시 발송. 구현은 FCM 하나지만, 테스트가 가짜 sender로 바꿔 끼우려고 인터페이스로 둔다.
 * 키 파일이 없으면 빈 자체가 없다(PushConfig) → 발송만 꺼지고 나머지 기능은 그대로.
 */
public interface PushSender {

    enum Result {
        SENT,
        /** 토큰이 더 이상 쓸 수 없다(앱 삭제 등). 기기 토큰을 지운다. */
        INVALID_TOKEN,
        /** 일시 오류·메시지 문제 등. 그대로 두고 다음 실행에 다시 보낸다. */
        FAILED
    }

    Result send(String token, PushMessage message);
}
