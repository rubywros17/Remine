package com.remine.server.service;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.dto.ScreenshotPageResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.support.AopUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 분류(LLM 호출)는 DB 트랜잭션 밖에서, 저장은 분류가 모두 끝난 뒤 짧은 트랜잭션으로 한다는 것과
 * 부분 실패·재전송 규칙을 실제 DB(H2)로 검증한다. 분류기는 스크립트된 가짜라 외부 호출은 없다.
 */
@SpringBootTest
class AnalyzeIntegrationTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 19, 12, 0);

    /** 분류가 불린 시점의 트랜잭션 상태와 DB 행 수를 기록하고, OCR에 FAIL이 있으면 실패한다. */
    static class ScriptedClassifier implements Classifier {
        final ScreenshotRepository repository;
        final List<Boolean> transactionActive = new CopyOnWriteArrayList<>();
        final List<Long> rowCountsDuringClassify = new CopyOnWriteArrayList<>();
        volatile boolean failing = true;

        ScriptedClassifier(ScreenshotRepository repository) {
            this.repository = repository;
        }

        @Override
        public ClassificationResult classify(String ocrText, byte[] jpegImage) {
            transactionActive.add(TransactionSynchronizationManager.isActualTransactionActive());
            rowCountsDuringClassify.add(repository.count());
            if (failing && ocrText.contains("FAIL")) {
                throw new ClassificationException(ClassificationException.Reason.CALL_FAILED, "HTTP 503");
            }
            return new ClassificationResult(Category.INFO, List.of("팁"), "요약");
        }
    }

    @TestConfiguration
    static class Config {
        @Bean
        @Primary
        ScriptedClassifier scriptedClassifier(ScreenshotRepository repository) {
            return new ScriptedClassifier(repository);
        }
    }

    @Autowired ScreenshotService service;
    @Autowired ScreenshotQueryService queryService;
    @Autowired ScreenshotPersister persister;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired ScriptedClassifier classifier;

    private Long deviceId;

    @BeforeEach
    void setUp() {
        deviceId = deviceRepository.save(new Device("token")).getId();
        classifier.transactionActive.clear();
        classifier.rowCountsDuringClassify.clear();
        classifier.failing = true;
    }

    private AnalyzeRequest request(String... idAndText) {
        // "id:텍스트" 형식
        List<Item> items = java.util.Arrays.stream(idAndText).map(s -> {
            String[] parts = s.split(":", 2);
            return new Item(parts[0], NOW, "앱", parts[1]);
        }).toList();
        return new AnalyzeRequest(items);
    }

    private Screenshot row(String assetId) {
        return screenshotRepository.findByDeviceAndLocalAssetIds(deviceId, List.of(assetId)).get(0);
    }

    @Test
    void 저장_컴포넌트는_트랜잭션_프록시다() {
        assertThat(AopUtils.isAopProxy(persister)).isTrue();
    }

    @Test
    void 분류는_트랜잭션_밖에서_하고_저장은_분류가_모두_끝난_뒤에_한다() {
        long before = screenshotRepository.count();

        AnalyzeResponse response = service.analyze(deviceId, request("a:팁1", "b:팁2", "c:팁3"));

        assertThat(response.analyzed()).hasSize(3);
        assertThat(classifier.transactionActive).hasSize(3).containsOnly(false);
        // 세 번의 분류가 진행되는 동안 아직 아무 행도 저장되지 않았다 → 분류가 먼저, 저장은 마지막에 한 번
        assertThat(classifier.rowCountsDuringClassify).containsOnly(before);
        assertThat(screenshotRepository.count()).isEqualTo(before + 3);
        assertThat(row("a").getAnalyzedAt()).isNotNull();
    }

    @Test
    void 일부_분류가_실패하면_그_캡처만_미분석으로_남기고_나머지는_저장한다() {
        AnalyzeResponse response = service.analyze(deviceId, request("ok1:팁1", "bad:FAIL 입니다", "ok2:팁2"));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("ok1", "ok2");
        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("bad", AnalyzeResponse.Reason.LLM_CALL_FAILED));
        // DB: 실패한 행도 존재하지만 분석 정보가 비어 있다
        Screenshot bad = row("bad");
        assertThat(bad.getAnalyzedAt()).isNull();
        assertThat(bad.getCategory()).isNull();
        assertThat(bad.getSummary()).isNull();
        assertThat(row("ok1").getAnalyzedAt()).isNotNull();
        assertThat(row("ok2").getCategory()).isEqualTo(Category.INFO);
    }

    @Test
    void 미분석_행은_목록과_요약에서_빠진다() {
        service.analyze(deviceId, request("ok1:팁1", "bad:FAIL", "ok2:팁2"));

        ScreenshotPageResponse list = queryService.list(deviceId, null, null, 0, 30);
        CategorySummaryResponse summary = queryService.summary(deviceId);

        assertThat(list.totalElements()).isEqualTo(2);
        assertThat(list.items()).extracting(item -> item.localAssetId()).containsExactlyInAnyOrder("ok1", "ok2");
        assertThat(list.items()).allSatisfy(item -> assertThat(item.category()).isNotNull());
        assertThat(summary.categories().stream().mapToLong(CategorySummaryResponse.Item::count).sum()).isEqualTo(2);
    }

    @Test
    void 같은_요청을_다시_보내면_실패했던_캡처만_재분석하고_중복_행을_만들지_않는다() {
        service.analyze(deviceId, request("ok1:팁1", "bad:FAIL", "ok2:팁2"));
        Long badId = row("bad").getId();
        long rowsAfterFirst = screenshotRepository.findByDeviceAndLocalAssetIds(deviceId, List.of("ok1", "bad", "ok2")).size();
        classifier.failing = false;
        classifier.transactionActive.clear();

        AnalyzeResponse retry = service.analyze(deviceId, request("ok1:팁1", "bad:FAIL", "ok2:팁2"));

        assertThat(retry.skipped()).containsExactlyInAnyOrder("ok1", "ok2");
        assertThat(retry.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("bad");
        assertThat(retry.failed()).isEmpty();
        assertThat(classifier.transactionActive).hasSize(1); // 이미 분석된 둘은 다시 분류하지 않는다
        Screenshot bad = row("bad");
        assertThat(bad.getId()).isEqualTo(badId); // 같은 행을 갱신
        assertThat(bad.getAnalyzedAt()).isNotNull();
        assertThat(screenshotRepository.findByDeviceAndLocalAssetIds(deviceId, List.of("ok1", "bad", "ok2")))
                .hasSize((int) rowsAfterFirst);
        assertThat(queryService.list(deviceId, null, null, 0, 30).totalElements()).isEqualTo(3);
    }
}
