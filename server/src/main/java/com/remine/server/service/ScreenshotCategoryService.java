package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.CategoryUpdateResponse;
import com.remine.server.exception.CategoryNotAllowedException;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.exception.ScreenshotNotAnalyzedException;
import com.remine.server.exception.ScreenshotNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 사용자 카테고리 수정(F-05). 검사 순서: 값 검증(400) → 기기(404) → 캡처 소유(404) → 분석 여부(409).
 * 값 검증이 존재 여부와 무관하므로 400/404 차이로 다른 기기의 id가 있는지 알아낼 수 없다.
 */
@Service
@RequiredArgsConstructor
@Transactional
public class ScreenshotCategoryService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;

    public CategoryUpdateResponse updateCategory(Long deviceId, Long screenshotId, String rawCategory) {
        Category category = parse(rawCategory);
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
        // 없는 id와 다른 기기의 캡처는 같은 조회 결과(없음)라 구분되지 않는다
        Screenshot screenshot = screenshotRepository.findByIdAndDeviceId(screenshotId, deviceId)
                .orElseThrow(ScreenshotNotFoundException::new);
        if (screenshot.getAnalyzedAt() == null) {
            throw new ScreenshotNotAnalyzedException();
        }
        screenshot.changeCategoryByUser(category); // 더티 체킹으로 UPDATE
        return CategoryUpdateResponse.of(screenshot);
    }

    private static Category parse(String raw) {
        if (raw == null) {
            throw new CategoryNotAllowedException();
        }
        try {
            return Category.valueOf(raw);
        } catch (IllegalArgumentException e) {
            throw new CategoryNotAllowedException();
        }
    }
}
