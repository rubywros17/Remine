package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.ScreenshotResponse;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** 태그 모아보기: 카테고리 없이 태그만으로, 표기가 달라도(공백·#·대소문자) 같은 태그를 전부 최신순으로. */
@SpringBootTest
class TagSearchIntegrationTest {

    @Autowired ScreenshotPersister persister;
    @Autowired ScreenshotQueryService queryService;
    @Autowired DeviceRepository deviceRepository;

    @Test
    void 태그로_찾으면_카테고리_상관없이_정규화한_같은_태그를_최신순으로_준다() {
        Long device = deviceRepository.save(new Device("token")).getId();
        LocalDateTime at = LocalDateTime.of(2026, 10, 20, 12, 0);
        save(device, "old", at.minusDays(30), Category.SHOPPING, "니트가디건");
        save(device, "new", at, Category.INFO, "니트 가디건");
        save(device, "other", at.minusDays(1), Category.SHOPPING, "청바지");

        List<ScreenshotResponse> items = queryService.list(device, null, "#니트 가디건", 0, 30).items();

        assertThat(items).extracting(ScreenshotResponse::localAssetId).containsExactly("new", "old");
        assertThat(items).extracting(ScreenshotResponse::category)
                .containsExactly(Category.INFO, Category.SHOPPING);
    }

    private void save(Long device, String assetId, LocalDateTime at, Category category, String tag) {
        persister.saveAll(device, List.of(new Outcome(new Item(assetId, at, "앱", "ocr"),
                new ClassificationResult(category, List.of(tag), "요약"))));
    }
}
