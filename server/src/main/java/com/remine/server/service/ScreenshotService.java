package com.remine.server.service;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.exception.BatchTooLargeException;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.service.ScreenshotPersister.Outcome;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 스크린샷 분석. <b>트랜잭션을 걸지 않는다</b>: 분류(느린 외부 LLM 호출)를 모두 끝낸 뒤
 * {@link ScreenshotPersister}가 한 번의 짧은 트랜잭션으로 저장한다. 호출은 순차이고 호출 간격 제한이 있어
 * 요청 하나에 담을 수 있는 캡처 수는 remine.analyze.max-batch-size로 제한한다.
 *
 * <p>로그에는 건수와 소요 시간만 남긴다. OCR 원문·이미지·키는 남기지 않는다.
 */
@Service
@RequiredArgsConstructor
public class ScreenshotService {

    private static final Logger log = LoggerFactory.getLogger(ScreenshotService.class);

    private final DeviceRepository deviceRepository;
    private final ScreenshotRepository screenshotRepository;
    private final Classifier classifier;
    private final ScreenshotPersister persister;
    private final RemineProperties properties;

    public AnalyzeResponse analyze(Long deviceId, AnalyzeRequest request) {
        long startedNanos = System.nanoTime();
        int requested = request.screenshots().size();
        int max = properties.analyze().maxBatchSize();
        if (requested > max) {
            throw new BatchTooLargeException(requested, max);
        }
        if (!deviceRepository.existsById(deviceId)) {
            throw new DeviceNotFoundException(deviceId);
        }

        List<String> assetIds = request.screenshots().stream().map(AnalyzeRequest.Item::localAssetId).toList();
        // 분석이 끝난 것 + 같은 요청 안에서 중복으로 들어온 것은 건너뛴다. 분석에 실패해 남은 행은 다시 분석한다.
        Set<String> seen = new HashSet<>(screenshotRepository.findAnalyzedLocalAssetIds(deviceId, assetIds));

        List<AnalyzeResponse.Result> analyzed = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        List<AnalyzeResponse.Failure> failed = new ArrayList<>();
        List<Outcome> outcomes = new ArrayList<>();

        // 1) 분류: 트랜잭션 밖에서 캡처마다 호출한다. 한 건이 실패해도 나머지는 계속 진행한다.
        for (AnalyzeRequest.Item item : request.screenshots()) {
            if (!seen.add(item.localAssetId())) {
                skipped.add(item.localAssetId());
                continue;
            }
            try {
                ClassificationResult result = classify(item.ocrText());
                outcomes.add(new Outcome(item, result));
                analyzed.add(new AnalyzeResponse.Result(
                        item.localAssetId(), result.category(), result.tags(), result.summary()));
            } catch (ClassificationException e) {
                outcomes.add(new Outcome(item, null));
                failed.add(new AnalyzeResponse.Failure(item.localAssetId(), toReason(e)));
            }
        }

        // 2) 저장: 짧은 트랜잭션 하나 (저장할 것이 없으면 호출하지 않는다)
        if (!outcomes.isEmpty()) {
            persister.saveAll(deviceId, outcomes);
        }

        log.info("analyze deviceId={} requested={} analyzed={} skipped={} failed={} elapsedMs={}",
                deviceId, requested, analyzed.size(), skipped.size(), failed.size(),
                (System.nanoTime() - startedNanos) / 1_000_000);
        return new AnalyzeResponse(analyzed, skipped, failed);
    }

    // 글자 없는 스크린샷은 LLM 호출 없이 '기타'로 처리한다. (spec 11장)
    // 이미지 수신 API가 생기면 "빈 OCR + 이미지"는 분류기로 보내도록 여기를 바꾼다.
    private ClassificationResult classify(String ocrText) {
        if (ocrText == null || ocrText.isBlank()) {
            return new ClassificationResult(Category.ETC, List.of(), "");
        }
        return classifier.classify(ocrText, null);
    }

    private static AnalyzeResponse.Reason toReason(ClassificationException e) {
        return e.reason() == ClassificationException.Reason.INVALID_RESPONSE
                ? AnalyzeResponse.Reason.LLM_INVALID_RESPONSE
                : AnalyzeResponse.Reason.LLM_CALL_FAILED;
    }
}
