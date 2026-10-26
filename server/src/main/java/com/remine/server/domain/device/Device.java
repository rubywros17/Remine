package com.remine.server.domain.device;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Device {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // 푸시 토큰은 갱신될 수 있으므로 unique 제약은 걸지 않는다. 토큰을 못 받았거나 FCM이 무효라고 하면 null(푸시만 안 간다).
    private String fcmToken;

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    public Device(String fcmToken) {
        this.fcmToken = blankToNull(fcmToken);
    }

    public void updateFcmToken(String fcmToken) {
        this.fcmToken = blankToNull(fcmToken);
    }

    /**
     * FCM이 등록 해제된 토큰이라고 할 때. 기기 행(캡처가 매달려 있음)은 두고 토큰만 지운다.
     * 보내는 사이 앱이 새 토큰을 올렸으면 그 새 토큰은 지우지 않는다.
     */
    public void clearFcmToken(String sentToken) {
        if (sentToken != null && sentToken.equals(this.fcmToken)) {
            this.fcmToken = null;
        }
    }

    private static String blankToNull(String token) {
        return token == null || token.isBlank() ? null : token;
    }
}
