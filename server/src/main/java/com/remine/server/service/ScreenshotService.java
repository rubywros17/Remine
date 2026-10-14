package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTag;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.tag.Tag;
import com.remine.server.domain.tag.TagRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.exception.DeviceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ScreenshotService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final ScreenshotTagRepository screenshotTagRepository;
    private final TagRepository tagRepository;
    private final Classifier classifier;

    @Transactional
    public AnalyzeResponse analyze(Long deviceId, AnalyzeRequest request) {
        Device device = deviceRepository.findById(deviceId)
                .orElseThrow(() -> new DeviceNotFoundException(deviceId));

        List<String> assetIds = request.screenshots().stream()
                .map(AnalyzeRequest.Item::localAssetId)
                .toList();
        // 이미 저장된 것 + 같은 요청 안에서 중복으로 들어온 것 모두 건너뛴다.
        Set<String> seen = new HashSet<>(screenshotRepository.findExistingLocalAssetIds(device.getId(), assetIds));

        List<AnalyzeResponse.Result> analyzed = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        Map<Screenshot, List<String>> tagNamesByScreenshot = new LinkedHashMap<>();

        for (AnalyzeRequest.Item item : request.screenshots()) {
            if (!seen.add(item.localAssetId())) {
                skipped.add(item.localAssetId());
                continue;
            }
            ClassificationResult result = classify(item.ocrText());

            Screenshot screenshot = new Screenshot(device, item.localAssetId(), item.takenAt(),
                    item.sourceApp(), item.ocrText());
            screenshot.applyAnalysis(result.category(), result.summary());
            screenshotRepository.save(screenshot);

            tagNamesByScreenshot.put(screenshot, result.tags());
            analyzed.add(new AnalyzeResponse.Result(
                    item.localAssetId(), result.category(), result.tags(), result.summary()));
        }

        linkTags(tagNamesByScreenshot);
        return new AnalyzeResponse(analyzed, skipped);
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

    // 글자 없는 스크린샷은 LLM 호출 없이 '기타'로 처리한다. (spec 11장)
    private ClassificationResult classify(String ocrText) {
        if (ocrText == null || ocrText.isBlank()) {
            return new ClassificationResult(Category.ETC, List.of(), "");
        }
        return classifier.classify(ocrText);
    }
}
