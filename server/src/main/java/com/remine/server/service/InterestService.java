package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.InterestRow;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.dto.InterestResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 반복해서 캡처한 관심사를 찾는다: 최근 windowDays일(taken_at) 안에 같은 태그가 minCount번 이상.
 * 태그는 저장 때 정규화돼 있어(TagCleaner·Tag.keyOf) 표기만 다른 태그도 한 태그로 센다.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class InterestService {

    private static final int RECENT_CAPTURES = 3;

    private final DeviceRepository deviceRepository;
    private final ScreenshotTagRepository screenshotTagRepository;
    private final RemineProperties properties;
    private final Clock clock;

    /** 감지된 관심사 하나. recent는 최신순 최대 3개, 대표 카테고리는 현재 category(사용자 수정 반영)의 최빈값. */
    public record Detected(Long tagId, String tag, Category category, int captureCount,
                           LocalDateTime lastCapturedAt, List<InterestRow> recent) {
    }

    public InterestResponse list(Long deviceId) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
        LocalDateTime now = LocalDateTime.now(clock);
        int spanDays = properties.interest().windowDays();
        return new InterestResponse(detect(deviceId, now).stream()
                .map(d -> new InterestResponse.Item(d.tag(), d.category(), d.captureCount(), spanDays,
                        Math.max(0, ChronoUnit.DAYS.between(d.lastCapturedAt().toLocalDate(), now.toLocalDate())),
                        d.recent().stream().map(r -> new InterestResponse.Capture(r.screenshotId(), r.localAssetId()))
                                .toList()))
                .toList());
    }

    /**
     * 정렬: 횟수 많은 순 → 마지막 캡처가 최근인 순 → 태그 이름순.
     * ponytail: 기간 안 행을 메모리에서 묶는다(쿼리 1번). 캡처량이 커지면 group by/having 집계 + 상위 N개만 상세 조회로.
     */
    public List<Detected> detect(Long deviceId, LocalDateTime now) {
        RemineProperties.Interest rule = properties.interest();
        List<InterestRow> rows = screenshotTagRepository.findInterestRows(deviceId, now.minusDays(rule.windowDays()));

        // 행이 최신순이라 태그별 목록도 최신순이다.
        Map<Long, List<InterestRow>> byTag = new LinkedHashMap<>();
        rows.forEach(row -> byTag.computeIfAbsent(row.tagId(), id -> new ArrayList<>()).add(row));

        return byTag.values().stream()
                .filter(captures -> captures.size() >= rule.minCount())
                .map(captures -> new Detected(captures.get(0).tagId(), captures.get(0).tagName(),
                        representative(captures), captures.size(), captures.get(0).takenAt(),
                        captures.subList(0, Math.min(RECENT_CAPTURES, captures.size()))))
                .sorted(Comparator.comparingInt(Detected::captureCount).reversed()
                        .thenComparing(Detected::lastCapturedAt, Comparator.reverseOrder())
                        .thenComparing(Detected::tag))
                .toList();
    }

    // 가장 많은 카테고리. 동점이면 더 최근 캡처의 카테고리(captures가 최신순이라 먼저 센 쪽이 이긴다).
    private static Category representative(List<InterestRow> captures) {
        Map<Category, Integer> counts = new LinkedHashMap<>();
        captures.forEach(c -> counts.merge(c.category(), 1, Integer::sum));
        Category best = null;
        for (Map.Entry<Category, Integer> e : counts.entrySet()) {
            if (best == null || e.getValue() > counts.get(best)) {
                best = e.getKey();
            }
        }
        return best;
    }
}
