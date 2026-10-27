package com.remine.server.push;

import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Firebase Admin SDK로 보낸다. 발송마다 결과와 FCM 오류 코드만 INFO로 남긴다(토큰·문구·태그·예외 메시지 없음).
 * 주간 발송과 dev 테스트 발송이 모두 여기를 지난다.
 */
public class FcmPushSender implements PushSender {

    /** 앱(MainActivity.kt)이 만드는 알림 채널. 이름이 다르면 안드로이드가 기본 채널로 보낸다. */
    public static final String CHANNEL_ID = "interest_alerts";

    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);

    private final FirebaseMessaging messaging;

    public FcmPushSender(FirebaseMessaging messaging) {
        this.messaging = messaging;
    }

    @Override
    public Result send(String token, PushMessage message) {
        try {
            messaging.send(toMessage(token, message));
            log.info("push result={}", Result.SENT);
            return Result.SENT;
        } catch (FirebaseMessagingException e) {
            Result result = resultOf(e.getMessagingErrorCode());
            log.info("push result={} code={}", result, e.getMessagingErrorCode());
            return result;
        } catch (RuntimeException e) {
            log.info("push result={} type={}", Result.FAILED, e.getClass().getSimpleName());
            return Result.FAILED;
        }
    }

    /**
     * notification(제목·본문)이 있어야 앱이 백그라운드·종료 상태일 때 시스템이 알림을 띄운다(data만 있으면 안 뜸).
     * 안드로이드는 우선순위 HIGH(절전 중에도 바로 전달) + 앱의 알림 채널.
     */
    static Message toMessage(String token, PushMessage message) {
        return Message.builder()
                .setToken(token)
                .setNotification(Notification.builder().setTitle(message.title()).setBody(message.body()).build())
                .setAndroidConfig(AndroidConfig.builder()
                        .setPriority(AndroidConfig.Priority.HIGH)
                        .setNotification(AndroidNotification.builder().setChannelId(CHANNEL_ID).build())
                        .build())
                .putAllData(message.data())
                .build();
    }

    /**
     * 토큰을 지우는 건 FCM이 "이 토큰은 끝났다"고 확실히 말할 때만.
     * INVALID_ARGUMENT는 토큰 형식뿐 아니라 메시지(payload) 문제일 수도 있어 토큰을 지우지 않고 재시도한다.
     */
    static Result resultOf(MessagingErrorCode code) {
        return code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.SENDER_ID_MISMATCH
                ? Result.INVALID_TOKEN
                : Result.FAILED;
    }
}
