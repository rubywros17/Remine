package com.remine.server.domain.screenshot;

import com.remine.server.domain.device.Device;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(
        uniqueConstraints = @UniqueConstraint(columnNames = {"device_id", "local_asset_id"}),
        // 기기별 최신순 목록 조회용
        indexes = @Index(columnList = "device_id, taken_at"))
public class Screenshot {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "device_id")
    private Device device;

    // 기기 앨범 내 이미지 식별자. 원본은 서버에 없고 이 값으로 앱이 기기에서 찾는다.
    @Column(name = "local_asset_id", nullable = false)
    private String localAssetId;

    @Column(nullable = false)
    private LocalDateTime takenAt;

    private String sourceApp;

    @Column(columnDefinition = "TEXT")
    private String ocrText;

    // 분석 전에는 null, 분석 후 채워진다.
    @Enumerated(EnumType.STRING)
    private Category category;

    // 모델이 처음 낸 카테고리. 분석 시 한 번 채워지고 이후 바뀌지 않는다(사용자 수정 후 정확도 측정의 기준값).
    @Enumerated(EnumType.STRING)
    private Category autoCategory;

    // category가 모델 값(AUTO)인지 사용자가 정한 값(USER)인지. 분석 전에는 null.
    @Enumerated(EnumType.STRING)
    private CategorySource categorySource;

    private String summary;

    private LocalDateTime analyzedAt;

    public Screenshot(Device device, String localAssetId, LocalDateTime takenAt,
                      String sourceApp, String ocrText) {
        this.device = device;
        this.localAssetId = localAssetId;
        this.takenAt = takenAt;
        this.sourceApp = sourceApp;
        this.ocrText = ocrText;
    }

    /** 분석에 실패해 남은 행을 같은 캡처의 재전송으로 다시 분석할 때 최신 입력으로 갱신한다. */
    public void refreshCapture(LocalDateTime takenAt, String sourceApp, String ocrText) {
        this.takenAt = takenAt;
        this.sourceApp = sourceApp;
        this.ocrText = ocrText;
    }

    /**
     * 분석 결과를 반영한다. category·autoCategory는 이 메서드와 {@link #changeCategoryByUser}로만 바뀐다(세터 없음).
     * 어떤 재분석 경로든 여기를 거치므로 사용자가 정한 카테고리(USER)는 덮어쓰지 않는다.
     * 요약은 내용 설명이라 카테고리와 독립으로 갱신한다.
     */
    public void applyAnalysis(Category category, String summary) {
        if (this.autoCategory == null) {
            this.autoCategory = category;
        }
        if (this.categorySource != CategorySource.USER) {
            this.category = category;
            this.categorySource = CategorySource.AUTO;
        }
        this.summary = summary;
        this.analyzedAt = LocalDateTime.now();
    }

    /** 사용자가 카테고리를 지정한다. 같은 값이어도 USER가 된다(= 사용자 확인). 분석되지 않은 행은 수정할 수 없다. */
    public void changeCategoryByUser(Category category) {
        if (analyzedAt == null) {
            throw new IllegalStateException("분석되지 않은 스크린샷은 카테고리를 수정할 수 없습니다");
        }
        this.category = category;
        this.categorySource = CategorySource.USER;
    }
}
