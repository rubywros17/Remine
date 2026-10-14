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
import java.util.List;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class ScreenshotService {

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final ScreenshotTagRepository screenshotTagRepository;
    private final TagRepository tagRepository;
    private final Classifier classifier;

    @Transactional
    public AnalyzeResponse analyze(AnalyzeRequest request) {
        Device device = deviceRepository.findById(request.deviceId())
                .orElseThrow(() -> new DeviceNotFoundException(request.deviceId()));

        List<String> assetIds = request.screenshots().stream()
                .map(AnalyzeRequest.Item::localAssetId)
                .toList();
        // 이미 저장된 것 + 같은 요청 안에서 중복으로 들어온 것 모두 건너뛴다.
        Set<String> seen = new HashSet<>(screenshotRepository.findExistingLocalAssetIds(device.getId(), assetIds));

        List<AnalyzeResponse.Result> analyzed = new ArrayList<>();
        List<String> skipped = new ArrayList<>();

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

            for (String tagName : result.tags()) {
                Tag tag = findOrCreateTag(tagName);
                screenshotTagRepository.save(new ScreenshotTag(screenshot, tag));
            }
            analyzed.add(new AnalyzeResponse.Result(
                    item.localAssetId(), result.category(), result.tags(), result.summary()));
        }
        return new AnalyzeResponse(analyzed, skipped);
    }

    // 글자 없는 스크린샷은 LLM 호출 없이 '기타'로 처리한다. (spec 11장)
    private ClassificationResult classify(String ocrText) {
        if (ocrText == null || ocrText.isBlank()) {
            return new ClassificationResult(Category.ETC, List.of(), "");
        }
        return classifier.classify(ocrText);
    }

    // ponytail: 태그마다 조회하는 N+1, 동시 요청 시 unique 충돌 가능. 트래픽이 생기면 일괄 조회 + 재시도로.
    private Tag findOrCreateTag(String name) {
        return tagRepository.findByName(name).orElseGet(() -> tagRepository.save(new Tag(name)));
    }
}
