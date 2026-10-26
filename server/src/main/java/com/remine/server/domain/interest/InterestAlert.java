package com.remine.server.domain.interest;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.tag.Tag;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 주간 집계가 고른 관심사 알림 후보. 기기당 한 주에 하나(unique device + week_start) → 집계를 몇 번 돌려도 결과가 같다.
 * 문구는 보낼 때 만든다(InterestPushService). PENDING → SENT, 그 주에 못 보내면 다음 발송 실행이 EXPIRED로 정리한다.
 */
@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(uniqueConstraints = @UniqueConstraint(columnNames = {"device_id", "week_start"}))
public class InterestAlert {

    public enum Status { PENDING, SENT, EXPIRED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "device_id")
    private Device device;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tag_id")
    private Tag tag;

    // 집계 당시 대표 카테고리. 알림을 누르면 이 카테고리 화면을 태그로 걸러 연다.
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Category category;

    // 집계 당시 횟수. "횟수가 크게 늘면 쿨다운 무시" 같은 규칙이 생기면 비교 기준이 된다.
    @Column(nullable = false)
    private int captureCount;

    // 집계한 주의 월요일(Asia/Seoul). 멱등 키이자 쿨다운 기준.
    @Column(name = "week_start", nullable = false)
    private LocalDate weekStart;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status;

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    private LocalDateTime sentAt;

    public InterestAlert(Device device, Tag tag, Category category, int captureCount, LocalDate weekStart) {
        this.device = device;
        this.tag = tag;
        this.category = category;
        this.captureCount = captureCount;
        this.weekStart = weekStart;
        this.status = Status.PENDING;
    }

    public void markSent(LocalDateTime now) {
        this.status = Status.SENT;
        this.sentAt = now;
    }
}
