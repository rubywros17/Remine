package com.remine.server.push;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.context.annotation.Conditional;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.type.AnnotatedTypeMetadata;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * remine.fcm.credentials-file(서비스 계정 키)이 있을 때만 {@link PushSender} 빈을 만든다.
 * 없으면 빈이 없고, InterestPushService가 기동 때 한 번 경고하고 발송을 건너뛴다.
 * 경로는 있는데 파일이 깨졌으면 기동이 실패한다(조용히 꺼지면 알아채기 어렵다).
 */
@Configuration
public class PushConfig {

    static final String CREDENTIALS_FILE = "remine.fcm.credentials-file";
    private static final String APP_NAME = "remine";

    @Bean
    @Conditional(CredentialsFilePresent.class)
    PushSender fcmPushSender(@Value("${" + CREDENTIALS_FILE + "}") String file) {
        FirebaseApp app = FirebaseApp.getApps().stream()
                .filter(a -> a.getName().equals(APP_NAME))
                .findFirst()
                .orElseGet(() -> FirebaseApp.initializeApp(options(Path.of(file)), APP_NAME));
        return new FcmPushSender(FirebaseMessaging.getInstance(app));
    }

    private static FirebaseOptions options(Path file) {
        try (InputStream in = Files.newInputStream(file)) {
            return FirebaseOptions.builder().setCredentials(GoogleCredentials.fromStream(in)).build();
        } catch (IOException e) {
            throw new IllegalStateException("Firebase 키 파일을 읽을 수 없습니다: " + CREDENTIALS_FILE, e);
        }
    }

    static class CredentialsFilePresent implements Condition {
        @Override
        public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
            String file = context.getEnvironment().getProperty(CREDENTIALS_FILE, "");
            return !file.isBlank() && Files.isRegularFile(Path.of(file));
        }
    }
}
