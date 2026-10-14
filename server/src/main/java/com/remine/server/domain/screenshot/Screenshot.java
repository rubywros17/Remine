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
@Table(uniqueConstraints = @UniqueConstraint(columnNames = {"device_id", "local_asset_id"}))
public class Screenshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
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

    public void applyAnalysis(Category category, String summary) {
        this.category = category;
        this.summary = summary;
        this.analyzedAt = LocalDateTime.now();
    }
}
