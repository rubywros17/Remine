package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.CategoryCountRow;
import com.remine.server.domain.screenshot.CategoryTagCountRow;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRow;
import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.dto.ScreenshotResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** 조회 전용 서비스. 모든 조회는 요청한 기기의 데이터로만 한정한다. */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ScreenshotQueryService {

    private static final int TOP_TAGS = 3;
    private static final int RECENT_ASSETS = 4;

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

    /** 쿼리 3번(개수 / 태그 빈도 / 최신 id)으로 모든 카테고리를 채운다. 카테고리 수와 쿼리 수는 무관하다. */
    public CategorySummaryResponse summary(Long deviceId) {
        requireDevice(deviceId);

        Map<Category, Long> counts = new EnumMap<>(Category.class);
        for (CategoryCountRow row : screenshotRepository.countByCategory(deviceId)) {
            counts.put(row.category(), row.count());
        }

        // 빈도 내림차순, 동점이면 이름순으로 정렬한 뒤 카테고리별 상위 3개만 남긴다.
        Map<Category, List<String>> topTags = new EnumMap<>(Category.class);
        screenshotTagRepository.countTagsByCategory(deviceId).stream()
                .sorted(Comparator.comparingLong(CategoryTagCountRow::count).reversed()
                        .thenComparing(CategoryTagCountRow::tagName))
                .forEach(row -> {
                    List<String> tags = topTags.computeIfAbsent(row.category(), c -> new ArrayList<>());
                    if (tags.size() < TOP_TAGS) {
                        tags.add(row.tagName());
                    }
                });

        Map<Category, List<String>> recent = new EnumMap<>(Category.class);
        for (Object[] row : screenshotRepository.findRecentAssetIdsByCategory(deviceId, RECENT_ASSETS)) {
            Category category = Category.valueOf(String.valueOf(row[0]));
            recent.computeIfAbsent(category, c -> new ArrayList<>()).add((String) row[1]);
        }

        List<CategorySummaryResponse.Item> items = new ArrayList<>();
        for (Category category : Category.values()) {
            items.add(new CategorySummaryResponse.Item(category,
                    counts.getOrDefault(category, 0L),
                    topTags.getOrDefault(category, List.of()),
                    recent.getOrDefault(category, List.of())));
        }
        return new CategorySummaryResponse(items);
    }

    private void requireDevice(Long deviceId) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
    }
}
