package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTag;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.tag.Tag;
import com.remine.server.domain.tag.TagRepository;
import com.remine.server.dto.AnalyzeRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 분류가 끝난 결과를 한 번의 짧은 트랜잭션으로 저장한다.
 * LLM 호출은 이 트랜잭션 밖(ScreenshotService)에서 끝낸 뒤에 들어오므로, 느린 외부 호출 동안 DB 연결·트랜잭션을 쥐지 않는다.
 * ScreenshotService와 다른 빈이어야 @Transactional 프록시가 적용된다(자기 호출 방지).
 */
@Component
@RequiredArgsConstructor
public class ScreenshotPersister {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final ScreenshotTagRepository screenshotTagRepository;
    private final TagRepository tagRepository;

    /** 캡처 하나의 분류 결과. result가 null이면 분류에 실패한 것이다(미분석으로 남긴다). */
    public record Outcome(AnalyzeRequest.Item item, ClassificationResult result) {

        public boolean failed() {
            return result == null;
        }
    }

    /**
     * 성공한 캡처는 분석 결과와 태그를 저장하고, 실패한 캡처는 category·summary·analyzed_at이 null인 행으로 남긴다.
     * 이미 같은 (device, localAssetId) 행이 있으면(앞선 요청에서 실패해 남은 행) 새로 만들지 않고 그 행을 갱신한다.
     *
     * TODO: 같은 (device, localAssetId)를 동시에 보내는 요청이 둘이면 unique 제약 충돌이 날 수 있다.
     *       (태그 이름 unique 충돌과 같은 계열 — 충돌 시 재조회·재시도 처리)
     */
    @Transactional
    public void saveAll(Long deviceId, List<Outcome> outcomes) {
        if (outcomes.isEmpty()) {
            return;
        }
        Device device = deviceRepository.getReferenceById(deviceId);
        Map<String, Screenshot> existing = screenshotRepository.findByDeviceAndLocalAssetIds(deviceId,
                        outcomes.stream().map(o -> o.item().localAssetId()).toList())
                .stream().collect(Collectors.toMap(Screenshot::getLocalAssetId, Function.identity()));

        Map<Screenshot, List<String>> tagNamesByScreenshot = new LinkedHashMap<>();
        for (Outcome outcome : outcomes) {
            AnalyzeRequest.Item item = outcome.item();
            Screenshot screenshot = existing.get(item.localAssetId());
            if (screenshot == null) {
                screenshot = new Screenshot(device, item.localAssetId(), item.takenAt(), item.sourceApp(), item.ocrText());
            } else {
                screenshot.refreshCapture(item.takenAt(), item.sourceApp(), item.ocrText());
            }
            if (!outcome.failed()) {
                screenshot.applyAnalysis(outcome.result().category(), outcome.result().summary());
                tagNamesByScreenshot.put(screenshot, outcome.result().tags());
            }
            screenshotRepository.save(screenshot);
        }
        linkTags(tagNamesByScreenshot);
    }

    // 요청 전체의 태그 이름을 모아 1번 조회하고, 없는 태그만 한 번에 생성한다.
    private void linkTags(Map<Screenshot, List<String>> tagNamesByScreenshot) {
        Set<String> names = tagNamesByScreenshot.values().stream()
                .flatMap(List::stream)
                .collect(Collectors.toSet());
        if (names.isEmpty()) {
            return;
        }
        Map<String, Tag> tags = tagRepository.findAllByNameIn(names).stream()
                .collect(Collectors.toMap(Tag::getName, Function.identity()));

        List<Tag> missing = names.stream()
                .filter(name -> !tags.containsKey(name))
                .map(Tag::new)
                .toList();
        // TODO: 동시 요청이 같은 새 태그를 만들면 tag.name unique 충돌 가능. 충돌 시 재조회·재시도 처리.
        tagRepository.saveAll(missing).forEach(tag -> tags.put(tag.getName(), tag));

        List<ScreenshotTag> links = new ArrayList<>();
        tagNamesByScreenshot.forEach((screenshot, tagNames) ->
                tagNames.forEach(name -> links.add(new ScreenshotTag(screenshot, tags.get(name)))));
        screenshotTagRepository.saveAll(links);
    }
}
