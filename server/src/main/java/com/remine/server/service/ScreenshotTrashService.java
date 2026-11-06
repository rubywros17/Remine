package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Collection;

/**
 * 앱 휴지통 표시. 넣으면 관심사 집계·푸시에서 빠지고, 되살리면 돌아온다. 행과 태그는 지우지 않는다.
 *
 * 앱이 실패한 요청을 다음 동기화 때 다시 보내므로 여러 번 보내도 결과가 같아야 한다:
 * 이 기기의 캡처만 바꾸고, 없는 id는 무시하며, 이미 휴지통에 있는 캡처의 시각은 그대로 둔다.
 * 목록·요약은 앱이 휴지통 항목을 직접 빼므로 서버에서는 거르지 않는다(거르면 개수가 두 번 줄어든다).
 */
@Service
@RequiredArgsConstructor
@Transactional
public class ScreenshotTrashService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final Clock clock;

    /** @return 새로 휴지통에 넣은 캡처 수 */
    public int trash(Long deviceId, Collection<String> assetIds) {
        requireDevice(deviceId);
        if (assetIds.isEmpty()) {
            return 0;
        }
        return screenshotRepository.markTrashed(deviceId, assetIds, LocalDateTime.now(clock));
    }

    /** @return 되살린 캡처 수 */
    public int restore(Long deviceId, Collection<String> assetIds) {
        requireDevice(deviceId);
        if (assetIds.isEmpty()) {
            return 0;
        }
        return screenshotRepository.clearTrashed(deviceId, assetIds);
    }

    private void requireDevice(Long deviceId) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
    }
}
