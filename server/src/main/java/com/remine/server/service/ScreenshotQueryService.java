package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRow;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.dto.ScreenshotResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** 조회 전용 서비스. 모든 조회는 요청한 기기의 데이터로만 한정한다. */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ScreenshotQueryService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final ScreenshotTagRepository screenshotTagRepository;

    public ScreenshotPageResponse list(Long deviceId, Category category, String tag, int page, int size) {
        requireDevice(deviceId);
        String tagFilter = (tag == null || tag.isBlank()) ? null : tag;

        Page<Screenshot> result = screenshotRepository.search(
                deviceId, category, tagFilter, PageRequest.of(page, size));

        List<Long> ids = result.getContent().stream().map(Screenshot::getId).toList();
        Map<Long, List<String>> tagsById = ids.isEmpty()
                ? Map.of()
                : screenshotTagRepository.findTagRows(ids).stream().collect(
                        Collectors.groupingBy(ScreenshotTagRow::screenshotId,
                                Collectors.mapping(ScreenshotTagRow::tagName, Collectors.toList())));

        List<ScreenshotResponse> items = result.getContent().stream()
                .map(s -> ScreenshotResponse.of(s, tagsById.getOrDefault(s.getId(), List.of())))
                .toList();
        return new ScreenshotPageResponse(items, result.getNumber(), result.getSize(),
                result.getTotalElements(), result.getTotalPages());
    }

    private void requireDevice(Long deviceId) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
    }
}
