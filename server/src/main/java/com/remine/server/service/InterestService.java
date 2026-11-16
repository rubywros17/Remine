package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestStatus;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.InterestRow;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.tag.Tag;
import com.remine.server.dto.InterestResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 반복해서 캡처한 관심사를 찾는다: 전체 기간에서 같은 태그가 minCount번 이상(넓은 태그 제외).
 * 마지막 캡처가 recentDays 이내면 RECENT, 넘으면 FORGOTTEN — 앱의 목적은 묵혀 둔 관심사를 다시 꺼내는 것이다.
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

    /**
     * 감지된 관심사 하나. recent는 최신순 최대 3개, 대표 카테고리는 현재 category(사용자 수정 반영)의 최빈값.
     * peakMonth는 장수가 가장 많은 달(동점이면 최근 달), latestMonthCount는 마지막 캡처가 있는 달의 장수.
     * linkedTags는 같은 캡처에 함께 붙은 **다른 관심사** 태그(관심사가 아닌 태그는 빼고, 이 목록의 정렬 순서).
     */
    public record Detected(Long tagId, String tag, Category category, InterestStatus status, int captureCount,
                           LocalDateTime lastCapturedAt, long dormantDays, YearMonth peakMonth, int peakMonthCount,
                           int latestMonthCount, List<InterestRow> recent, List<String> linkedTags) {

        public boolean forgotten() {
            return status == InterestStatus.FORGOTTEN;
        }

        Detected withLinkedTags(List<String> tags) {
            return new Detected(tagId, tag, category, status, captureCount, lastCapturedAt, dormantDays, peakMonth,
                    peakMonthCount, latestMonthCount, recent, tags);
        }
    }

    public InterestResponse list(Long deviceId) {
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }
        RemineProperties.Interest rule = properties.interest();
        return new InterestResponse(rule.recentDays(), rule.minCount(), detect(deviceId, LocalDateTime.now(clock))
                .stream()
                .map(d -> new InterestResponse.Item(d.tag(), d.category(), d.status(), d.captureCount(),
                        d.dormantDays(), d.peakMonth().getMonthValue(), d.peakMonthCount(),
                        d.lastCapturedAt().getMonthValue(), d.latestMonthCount(),
                        d.recent().stream()
                                .map(r -> new InterestResponse.Capture(r.screenshotId(), r.localAssetId(), r.takenAt()))
                                .toList(),
                        d.linkedTags()))
                .toList());
    }

    /**
     * 정렬: FORGOTTEN(장수 많은 순 → 오래 안 본 순) → RECENT(장수 많은 순 → 최근 순) → 태그 이름순.
     * 쿼리 1번으로 읽고 상태·월별 집계는 메모리에서 나눈다(ScreenshotTagRepository#findInterestRows의 ponytail 참고).
     */
    public List<Detected> detect(Long deviceId, LocalDateTime now) {
        RemineProperties.Interest rule = properties.interest();
        Set<String> broad = rule.broadTags().stream().map(Tag::keyOf).collect(Collectors.toSet());
        List<InterestRow> rows = screenshotTagRepository.findInterestRows(deviceId);

        // 행이 최신순이라 태그별 목록도 최신순이다.
        Map<Long, List<InterestRow>> byTag = new LinkedHashMap<>();
        rows.forEach(row -> byTag.computeIfAbsent(row.tagId(), id -> new ArrayList<>()).add(row));

        List<Detected> detected = byTag.values().stream()
                .filter(captures -> captures.size() >= rule.minCount())
                .filter(captures -> !broad.contains(Tag.keyOf(captures.get(0).tagName())))
                .map(captures -> detected(captures, now, rule.recentDays()))
                .sorted(Comparator.comparing(Detected::status)
                        .thenComparing(Comparator.comparingInt(Detected::captureCount).reversed())
                        .thenComparingLong(d -> d.forgotten() ? -d.dormantDays() : d.dormantDays())
                        .thenComparing(Detected::tag))
                .toList();
        return withLinks(detected, rows);
    }

    private static Detected detected(List<InterestRow> captures, LocalDateTime now, int recentDays) {
        InterestRow latest = captures.get(0);
        long dormantDays = Math.max(0, ChronoUnit.DAYS.between(latest.takenAt().toLocalDate(), now.toLocalDate()));
        // 최신순으로 넣어 동점이면 먼저 넣은(최근) 달이 이긴다.
        Map<YearMonth, Integer> byMonth = new LinkedHashMap<>();
        captures.forEach(c -> byMonth.merge(YearMonth.from(c.takenAt()), 1, Integer::sum));
        Map.Entry<YearMonth, Integer> peak = maxFirst(byMonth);
        return new Detected(latest.tagId(), latest.tagName(), maxFirst(countByCategory(captures)).getKey(),
                dormantDays <= recentDays ? InterestStatus.RECENT : InterestStatus.FORGOTTEN,
                captures.size(), latest.takenAt(), dormantDays, peak.getKey(), peak.getValue(),
                byMonth.get(YearMonth.from(latest.takenAt())),
                captures.subList(0, Math.min(RECENT_CAPTURES, captures.size())), List.of());
    }

    /** 이미 읽은 행으로만 묶는다(쿼리 추가 없음): 캡처별 태그 → 관심사끼리 겹치면 연결. */
    private static List<Detected> withLinks(List<Detected> detected, List<InterestRow> rows) {
        Set<Long> interestIds = detected.stream().map(Detected::tagId).collect(Collectors.toSet());
        Map<Long, Set<Long>> tagsByShot = new HashMap<>();
        rows.stream().filter(r -> interestIds.contains(r.tagId()))
                .forEach(r -> tagsByShot.computeIfAbsent(r.screenshotId(), id -> new HashSet<>()).add(r.tagId()));
        Map<Long, Set<Long>> links = new HashMap<>();
        for (Set<Long> tags : tagsByShot.values()) {
            for (Long tag : tags) {
                links.computeIfAbsent(tag, id -> new HashSet<>()).addAll(tags);
            }
        }
        return detected.stream().map(d -> d.withLinkedTags(detected.stream()
                        .filter(o -> !o.tagId().equals(d.tagId())
                                && links.getOrDefault(d.tagId(), Set.of()).contains(o.tagId()))
                        .map(Detected::tag)
                        .toList()))
                .toList();
    }

    // 카테고리별 장수. 최신순으로 세서 동점이면 더 최근 캡처의 카테고리가 이긴다.
    private static Map<Category, Integer> countByCategory(List<InterestRow> captures) {
        Map<Category, Integer> counts = new LinkedHashMap<>();
        captures.forEach(c -> counts.merge(c.category(), 1, Integer::sum));
        return counts;
    }

    // 값이 가장 큰 항목. 동점이면 먼저 넣은 항목.
    private static <K> Map.Entry<K, Integer> maxFirst(Map<K, Integer> counts) {
        Map.Entry<K, Integer> best = null;
        for (Map.Entry<K, Integer> e : counts.entrySet()) {
            if (best == null || e.getValue() > best.getValue()) {
                best = e;
            }
        }
        return best;
    }
}
