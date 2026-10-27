package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;

/**
 * 앱이 "보내지 말았어야 할 캡처"라고 알려 준 것(예: Remine 자기 화면 캡처)을 지운다.
 * 이 기기의 캡처만 지우고, 없는 id는 무시한다(여러 번 보내도 결과가 같다).
 * 관심사·카테고리 개수는 조회할 때 다시 세므로 따로 고칠 것이 없다.
 */
@Service
@RequiredArgsConstructor
@Transactional
public class ScreenshotForgetService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final ScreenshotTagRepository screenshotTagRepository;

    /** @return 지운 캡처 수 */
    public int forget(Long deviceId, Collection<String> assetIds) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
        if (assetIds.isEmpty()) {
            return 0;
        }
        // 연결(태그)을 먼저 지워야 외래 키에 걸리지 않는다
        screenshotTagRepository.deleteByDeviceAndAssetIds(deviceId, assetIds);
        return screenshotRepository.deleteByDeviceAndAssetIds(deviceId, assetIds);
    }
}
