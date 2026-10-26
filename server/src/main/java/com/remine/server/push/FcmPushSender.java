package com.remine.server.push;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Firebase Admin SDK로 보낸다. 로그에는 오류 코드만 남긴다(토큰·문구·예외 메시지 없음). */
public class FcmPushSender implements PushSender {

    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);

    private final FirebaseMessaging messaging;

    public FcmPushSender(FirebaseMessaging messaging) {
        this.messaging = messaging;
    }

    @Override
    public Result send(String token, PushMessage message) {
        try {
            messaging.send(Message.builder()
                    .setToken(token)
                    // notification이 있어야 앱이 백그라운드·종료 상태일 때 시스템이 알림을 띄운다.
                    .setNotification(Notification.builder().setTitle(message.title()).setBody(message.body()).build())
                    .putAllData(message.data())
                    .build());
            return Result.SENT;
        } catch (FirebaseMessagingException e) {
            log.warn("push failed code={}", e.getMessagingErrorCode());
            return resultOf(e.getMessagingErrorCode());
        } catch (RuntimeException e) {
            log.warn("push failed type={}", e.getClass().getSimpleName());
            return Result.FAILED;
        }
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
