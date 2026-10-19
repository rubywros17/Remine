package com.remine.server.service;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationException.Reason;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.exception.BatchTooLargeException;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotServiceTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 14, 12, 0);

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @Mock Classifier classifier;
    @Mock ScreenshotPersister persister;
    @Captor ArgumentCaptor<List<Outcome>> outcomes;

    private ScreenshotService service;

    private static RemineProperties properties(int maxBatchSize) {
        return new RemineProperties(RemineProperties.ClassifierType.FAKE,
                new RemineProperties.Llm(150, new RemineProperties.Gemini("m", 1.0, "http://localhost:1",
                        Duration.ofSeconds(1), Duration.ofSeconds(1), 0)),
                new RemineProperties.Analyze(maxBatchSize),
                new RemineProperties.Image(1048576, 1024, 25_000_000L, 12582912, 5242880));
    }

    @BeforeEach
    void setUp() {
        service = new ScreenshotService(deviceRepository, screenshotRepository, classifier, persister, properties(20));
    }

    private void givenDevice() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
    }

    private AnalyzeRequest request(Item... items) {
        return new AnalyzeRequest(List.of(items));
    }

    @Test
    void 새_스크린샷은_분류해서_저장을_맡긴다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("39,000원 구매", null))
                .thenReturn(new ClassificationResult(Category.SHOPPING, List.of("구매"), "요약"));

        AnalyzeResponse response = service.analyze(1L, request(new Item("a1", NOW, "쿠팡", "39,000원 구매")));

        assertThat(response.analyzed()).hasSize(1);
        assertThat(response.analyzed().get(0).category()).isEqualTo(Category.SHOPPING);
        assertThat(response.skipped()).isEmpty();
        assertThat(response.failed()).isEmpty();
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue()).hasSize(1);
        assertThat(outcomes.getValue().get(0).failed()).isFalse();
    }

    @Test
    void 이미_분석된_localAssetId는_건너뛴다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of("a1"));

        AnalyzeResponse response = service.analyze(1L, request(new Item("a1", NOW, null, "구매")));

        assertThat(response.analyzed()).isEmpty();
        assertThat(response.skipped()).containsExactly("a1");
        verify(classifier, never()).classify(anyString(), any());
        verify(persister, never()).saveAll(any(), any()); // 저장할 것이 없으면 호출하지 않는다
    }

    @Test
    void 같은_요청_안의_중복_localAssetId도_한_번만_처리한다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("글", null)).thenReturn(new ClassificationResult(Category.ETC, List.of(), "글"));

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("a1", NOW, null, "글"), new Item("a1", NOW, null, "글")));

        assertThat(response.analyzed()).hasSize(1);
        assertThat(response.skipped()).containsExactly("a1");
    }

    @Test
    void 글자_없는_스크린샷은_분류기를_거치지_않고_기타로_저장한다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("a1", NOW, null, "  "), new Item("a2", NOW, null, null)));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::category)
                .containsExactly(Category.ETC, Category.ETC);
        verify(classifier, never()).classify(anyString(), any());
    }

    @Test
    void 등록되지_않은_기기면_예외이고_아무것도_하지_않는다() {
        when(deviceRepository.existsById(99L)).thenReturn(false);

        assertThatThrownBy(() -> service.analyze(99L, request(new Item("a1", NOW, null, "x"))))
                .isInstanceOf(DeviceNotFoundException.class);
        verifyNoInteractions(classifier, persister);
    }

    @Test
    void 일부가_실패해도_나머지는_저장하고_실패_건을_응답에_표시한다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("성공", null)).thenReturn(new ClassificationResult(Category.INFO, List.of("팁"), "요약"));
        when(classifier.classify("호출 실패", null)).thenThrow(new ClassificationException(Reason.CALL_FAILED, "HTTP 503"));
        when(classifier.classify("형식 오류", null))
                .thenThrow(new ClassificationException(Reason.INVALID_RESPONSE, "응답 형식 오류"));

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("ok", NOW, null, "성공"),
                new Item("bad1", NOW, null, "호출 실패"),
                new Item("bad2", NOW, null, "형식 오류")));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("ok");
        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("bad1", AnalyzeResponse.Reason.LLM_CALL_FAILED),
                new AnalyzeResponse.Failure("bad2", AnalyzeResponse.Reason.LLM_INVALID_RESPONSE));
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue()).extracting(o -> o.item().localAssetId()).containsExactly("ok", "bad1", "bad2");
        assertThat(outcomes.getValue()).extracting(Outcome::failed).containsExactly(false, true, true);
    }

    @Test
    void 전부_실패해도_요청은_정상_응답이고_실패_행은_미분석으로_남긴다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify(anyString(), isNull()))
                .thenThrow(new ClassificationException(Reason.CALL_FAILED, "HTTP 429 RESOURCE_EXHAUSTED"));

        AnalyzeResponse response = service.analyze(1L, request(new Item("a", NOW, null, "x"), new Item("b", NOW, null, "y")));

        assertThat(response.analyzed()).isEmpty();
        assertThat(response.failed()).hasSize(2);
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue()).allMatch(Outcome::failed);
    }

    @Test
    void 요청당_최대_항목_수를_넘으면_예외이고_분류도_저장도_하지_않는다() {
        List<Item> items = new ArrayList<>(IntStream.rangeClosed(1, 21)
                .mapToObj(i -> new Item("a" + i, NOW, null, "x")).toList());

        assertThatThrownBy(() -> service.analyze(1L, new AnalyzeRequest(items)))
                .isInstanceOfSatisfying(BatchTooLargeException.class, e -> {
                    assertThat(e.requested()).isEqualTo(21);
                    assertThat(e.max()).isEqualTo(20);
                    assertThat(e.getMessage()).contains("최대 20장").contains("21장");
                });
        verifyNoInteractions(deviceRepository, screenshotRepository, classifier, persister);
    }

    @Test
    void 최대_항목_수는_설정값을_따른다() {
        ScreenshotService small = new ScreenshotService(
                deviceRepository, screenshotRepository, classifier, persister, properties(2));
        List<Item> items = List.of(new Item("a", NOW, null, "x"), new Item("b", NOW, null, "x"),
                new Item("c", NOW, null, "x"));

        assertThatThrownBy(() -> small.analyze(1L, new AnalyzeRequest(items)))
                .isInstanceOf(BatchTooLargeException.class)
                .hasMessageContaining("최대 2장");
    }
}
