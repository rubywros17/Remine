package com.remine.server.service;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.ImageDecision;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.classifier.UsageMeter;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.exception.BatchTooLargeException;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.image.ImageResizer;
import com.remine.server.image.InvalidImageException;
import com.remine.server.service.ScreenshotPersister.Outcome;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;

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
    private final TagCleaner tagCleaner;
    private final UsageMeter meter;
    private final Set<InProgressKey> inProgress = ConcurrentHashMap.newKeySet();

    private record InProgressKey(Long deviceId, String localAssetId) {
    }

    /** 이미지 없는 요청(JSON). */
    public AnalyzeResponse analyze(Long deviceId, AnalyzeRequest request) {
        return analyze(deviceId, request, Map.of());
    }

    /**
     * @param images localAssetId → JPEG 바이트. 요청 처리 중 지역 변수로만 다루며 저장·로그하지 않는다.
     *               쓰지 않는 이미지(이미 분석됨, 분류기가 쓰지 않는다고 판단)는 디코딩하지 않고 건수만 센다.
     */
    public AnalyzeResponse analyze(Long deviceId, AnalyzeRequest request, Map<String, byte[]> images) {
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
        // 같은 캡처를 다른 요청이 분석 중이면(앱이 타임아웃 뒤 다시 보낸 경우) 중복 분석하지 않고 IN_PROGRESS로 돌려준다.
        // 선점은 원자적으로, 해제는 예외가 나도 반드시 한다(영구 IN_PROGRESS 방지).
        // ponytail: 서버 1대 전제의 메모리 Set. 여러 대로 늘리면 DB 상태(ANALYZING 행)로 옮긴다.
        List<InProgressKey> claimed = new ArrayList<>();
        Set<String> busy = new HashSet<>();
        try {
            for (String assetId : new HashSet<>(assetIds)) {
                InProgressKey key = new InProgressKey(deviceId, assetId);
                if (inProgress.add(key)) {
                    claimed.add(key);
                } else {
                    busy.add(assetId);
                }
            }
            return analyzeClaimed(deviceId, request, images, assetIds, busy, startedNanos);
        } finally {
            claimed.forEach(inProgress::remove);
        }
    }

    /** 선점한 뒤의 본문. 분석 완료 여부는 선점 뒤에 조회해야 방금 끝난 요청과 겹쳐 다시 분석하지 않는다. */
    private AnalyzeResponse analyzeClaimed(Long deviceId, AnalyzeRequest request, Map<String, byte[]> images,
                                           List<String> assetIds, Set<String> busy, long startedNanos) {
        int requested = request.screenshots().size();
        // 분석이 끝난 것 + 같은 요청 안에서 중복으로 들어온 것은 건너뛴다. 분석에 실패해 남은 행은 다시 분석한다.
        Set<String> seen = new HashSet<>(screenshotRepository.findAnalyzedLocalAssetIds(deviceId, assetIds));

        List<AnalyzeResponse.Result> analyzed = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        List<AnalyzeResponse.Failure> failed = new ArrayList<>();
        List<Outcome> outcomes = new ArrayList<>();
        ImageStats stats = new ImageStats(images.size());

        // 1) 이미지 준비: 쓸 이미지만 검증·축소한다. 이미지 문제는 그 캡처만 미분석으로 남긴다(앱이 reason에 따라 다시 보낸다).
        //    글자도 이미지도 없는 캡처는 LLM 없이 '기타'다(spec 11장).
        List<AnalyzeRequest.Item> toClassify = new ArrayList<>();
        List<Classifier.Input> inputs = new ArrayList<>();
        for (AnalyzeRequest.Item item : request.screenshots()) {
            byte[] image = images.get(item.localAssetId());
            if (!seen.add(item.localAssetId())) {
                skipped.add(item.localAssetId());
                if (image != null) {
                    stats.ignore("ALREADY_ANALYZED");
                }
                continue;
            }
            if (busy.contains(item.localAssetId())) {
                failed.add(new AnalyzeResponse.Failure(item.localAssetId(), AnalyzeResponse.Reason.IN_PROGRESS));
                if (image != null) {
                    stats.ignore("IN_PROGRESS");
                }
                continue;
            }
            byte[] usable;
            try {
                usable = prepareImage(item, image, stats);
            } catch (ImageRejectedException e) {
                outcomes.add(new Outcome(item, null));
                failed.add(new AnalyzeResponse.Failure(item.localAssetId(), e.reason));
                continue;
            }
            boolean blank = item.ocrText() == null || item.ocrText().isBlank();
            if (blank && usable == null) {
                succeed(item, new ClassificationResult(Category.ETC, List.of(), ""), outcomes, analyzed);
                continue;
            }
            toClassify.add(item);
            inputs.add(new Classifier.Input(blank ? "" : item.ocrText(), usable));
        }

        // 2) 분류: 트랜잭션 밖에서 한 번에 넘긴다(LLM 분류기는 여러 장을 한 요청으로 묶는다). 한 건이 실패해도 나머지는 계속 진행한다.
        //    태그는 여기서 정리해 응답과 저장이 같은 태그를 쓴다.
        List<Classifier.Classified> classified = inputs.isEmpty() ? List.of() : classifier.classifyAll(inputs);
        for (int i = 0; i < toClassify.size(); i++) {
            AnalyzeRequest.Item item = toClassify.get(i);
            Classifier.Classified c = classified.get(i);
            if (c.error() != null) {
                outcomes.add(new Outcome(item, null));
                failed.add(new AnalyzeResponse.Failure(item.localAssetId(), toReason(c.error())));
            } else {
                ClassificationResult raw = c.result();
                succeed(item, new ClassificationResult(raw.category(), tagCleaner.clean(raw.tags()), raw.summary()),
                        outcomes, analyzed);
            }
        }

        // 3) 저장: 짧은 트랜잭션 하나 (저장할 것이 없으면 호출하지 않는다)
        if (!outcomes.isEmpty()) {
            persister.saveAll(deviceId, outcomes);
        }

        long endedNanos = System.nanoTime();
        meter.recordRequest(startedNanos, endedNanos);
        log.info("analyze deviceId={} requested={} analyzed={} skipped={} failed={} elapsedMs={}",
                deviceId, requested, analyzed.size(), skipped.size(), failed.size(),
                (endedNanos - startedNanos) / 1_000_000);
        if (stats.received > 0) {
            // 이미지 관련 로그는 건수·바이트 수·사유 코드만. 이미지 내용은 남기지 않는다.
            log.info("analyze images received={} used={} rejected={} ignored={} bytesIn={} bytesUsed={}",
                    stats.received, stats.used, stats.rejected, stats.ignored, stats.bytesIn, stats.bytesUsed);
        }
        return new AnalyzeResponse(analyzed, skipped, failed);
    }

    /**
     * 이 캡처의 이미지를 분류에 쓸 수 있으면 검증·축소해서 돌려주고, 쓰지 않으면 null(건수만 센다).
     * 쓸지 말지는 분류기가 정한다(기준값 이상·전화번호 마스킹·미지원이면 이미지를 디코딩조차 하지 않는다).
     */
    private byte[] prepareImage(AnalyzeRequest.Item item, byte[] image, ImageStats stats) {
        if (image == null) {
            return null;
        }
        stats.bytesIn += image.length;
        ImageDecision decision = classifier.imageDecision(item.ocrText());
        if (decision != ImageDecision.USE) {
            stats.ignore(String.valueOf(decision));
            return null;
        }
        RemineProperties.Image policy = properties.image();
        if (image.length > policy.maxBytes()) {
            stats.rejected++;
            throw new ImageRejectedException(AnalyzeResponse.Reason.IMAGE_TOO_LARGE);
        }
        try {
            byte[] normalized = ImageResizer.normalizeJpeg(image, policy.maxLongSide(), policy.maxPixels());
            stats.used++;
            stats.bytesUsed += normalized.length;
            return normalized;
        } catch (InvalidImageException e) {
            stats.rejected++;
            throw new ImageRejectedException(AnalyzeResponse.Reason.IMAGE_INVALID);
        }
    }

    private static void succeed(AnalyzeRequest.Item item, ClassificationResult result, List<Outcome> outcomes,
                                List<AnalyzeResponse.Result> analyzed) {
        outcomes.add(new Outcome(item, result));
        analyzed.add(new AnalyzeResponse.Result(item.localAssetId(), result.category(), result.tags(), result.summary()));
    }

    /** 이미지 때문에 이 캡처만 실패 처리한다. 메시지·원인 없이 사유 코드만 담는다. */
    private static final class ImageRejectedException extends RuntimeException {
        private final AnalyzeResponse.Reason reason;

        ImageRejectedException(AnalyzeResponse.Reason reason) {
            super(null, null, false, false);
            this.reason = reason;
        }
    }

    /** 이미지 처리 집계. 건수·바이트 수·사유 코드만 담는다. */
    private static final class ImageStats {
        final int received;
        int used;
        int rejected;
        long bytesIn;
        long bytesUsed;
        final Map<String, Integer> ignored = new TreeMap<>();

        ImageStats(int received) {
            this.received = received;
        }

        void ignore(String reasonCode) {
            ignored.merge(reasonCode, 1, Integer::sum);
        }
    }

    private static AnalyzeResponse.Reason toReason(ClassificationException e) {
        return e.reason() == ClassificationException.Reason.INVALID_RESPONSE
                ? AnalyzeResponse.Reason.LLM_INVALID_RESPONSE
                : AnalyzeResponse.Reason.LLM_CALL_FAILED;
    }
}
