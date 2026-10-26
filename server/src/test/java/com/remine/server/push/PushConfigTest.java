package com.remine.server.push;

import com.google.firebase.messaging.MessagingErrorCode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;

/** 키 파일이 없으면 sender 빈이 없다(푸시만 꺼짐). 토큰을 지우는 오류 코드는 둘뿐. */
class PushConfigTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(PushConfig.class);

    @Test
    void 키_경로가_비었으면_sender가_없다() {
        runner.withPropertyValues("remine.fcm.credentials-file=")
                .run(context -> assertThat(context).hasNotFailed().doesNotHaveBean(PushSender.class));
    }

    @Test
    void 키_파일이_없으면_sender가_없다() {
        runner.withPropertyValues("remine.fcm.credentials-file=build/no-such-firebase-key.json")
                .run(context -> assertThat(context).hasNotFailed().doesNotHaveBean(PushSender.class));
    }

    @Test
    void 등록_해제_오류만_토큰_무효로_본다() {
        assertThat(FcmPushSender.resultOf(MessagingErrorCode.UNREGISTERED)).isEqualTo(PushSender.Result.INVALID_TOKEN);
        assertThat(FcmPushSender.resultOf(MessagingErrorCode.SENDER_ID_MISMATCH))
                .isEqualTo(PushSender.Result.INVALID_TOKEN);
        // 메시지 문제일 수도 있다 → 토큰을 지우지 않고 재시도
        assertThat(FcmPushSender.resultOf(MessagingErrorCode.INVALID_ARGUMENT)).isEqualTo(PushSender.Result.FAILED);
        assertThat(FcmPushSender.resultOf(MessagingErrorCode.UNAVAILABLE)).isEqualTo(PushSender.Result.FAILED);
        assertThat(FcmPushSender.resultOf(null)).isEqualTo(PushSender.Result.FAILED);
    }
}
