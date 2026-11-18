package com.remine.server.service;

import com.remine.server.classifier.ClassificationException;
import com.remine.server.classifier.ClassificationException.Reason;
import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.classifier.RemineProperties;
import com.remine.server.classifier.UsageMeter;
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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotServiceTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 14, 12, 0);
    /** 기기 등록 시각. 기존 테스트의 캡처(NOW)는 이보다 뒤라 새 스크린샷이다. */
    private static final LocalDateTime REGISTERED = NOW.minusDays(1);

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @Mock Classifier classifier;
    @Mock ScreenshotPersister persister;
    @Mock OlderQuota olderQuota;
    @Captor ArgumentCaptor<List<Outcome>> outcomes;

    private ScreenshotService service;

    private static RemineProperties properties(int maxBatchSize) {
        return properties(maxBatchSize, Duration.ofMinutes(4));
    }

    private static RemineProperties properties(int maxBatchSize, Duration deadline) {
        return new RemineProperties(RemineProperties.ClassifierType.FAKE,
                new RemineProperties.Llm(150, new RemineProperties.Gemini("m", 1.0, "http://localhost:1",
                        Duration.ofSeconds(1), Duration.ofSeconds(1), 0), new RemineProperties.Batch(10, 5)),
                new RemineProperties.Analyze(maxBatchSize, deadline, 300, 400, 70),
                new RemineProperties.Image(1048576, 1024, 25_000_000L, 12582912, 5242880),
                new RemineProperties.Tags(List.of("장바구니", "쇼핑")),
                new RemineProperties.Interest(30, 3, 28, List.of()));
    }

    private static ScreenshotService service(RemineProperties properties, DeviceRepository devices,
                                             ScreenshotRepository screenshots, Classifier classifier,
                                             ScreenshotPersister persister, OlderQuota olderQuota) {
        return new ScreenshotService(devices, screenshots, classifier, persister, properties, new TagCleaner(properties),
                new UsageMeter(), olderQuota);
    }

    @BeforeEach
    void setUp() {
        service = service(properties(20), deviceRepository, screenshotRepository, classifier, persister, olderQuota);
        // 서비스는 classifyAll로 넘긴다. 기본 구현(한 장씩 classify)을 그대로 타게 해서 classify 스텁으로 검증한다.
        lenient().when(classifier.classifyAll(any(), any())).thenCallRealMethod();
        lenient().when(classifier.classifyAllCounted(any(), any())).thenCallRealMethod();
    }

    private void givenDevice() {
        when(deviceRepository.findCreatedAtById(1L)).thenReturn(Optional.of(REGISTERED));
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
    void 모델_태그는_정리한_뒤_응답과_저장에_같이_쓴다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("가디건", null)).thenReturn(new ClassificationResult(Category.SHOPPING,
                List.of("#니트 가디건", "니트가디건", "장바구니", "쇼핑", " "), "요약"));

        AnalyzeResponse response = service.analyze(1L, request(new Item("a1", NOW, null, "가디건")));

        assertThat(response.analyzed().get(0).tags()).containsExactly("니트 가디건");
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue().get(0).result().tags()).containsExactly("니트 가디건");
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
        when(deviceRepository.findCreatedAtById(99L)).thenReturn(Optional.empty());

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
        ScreenshotService small = service(properties(2), deviceRepository, screenshotRepository, classifier, persister,
                olderQuota);
        List<Item> items = List.of(new Item("a", NOW, null, "x"), new Item("b", NOW, null, "x"),
                new Item("c", NOW, null, "x"));

        assertThatThrownBy(() -> small.analyze(1L, new AnalyzeRequest(items)))
                .isInstanceOf(BatchTooLargeException.class)
                .hasMessageContaining("최대 2장");
    }

    // ---- 이미지 입력: 분류기 판정 표 ----

    private static byte[] jpeg(int width, int height) {
        try {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(width, height,
                    java.awt.image.BufferedImage.TYPE_INT_RGB), "jpeg", out);
            return out.toByteArray();
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    private AnalyzeResponse analyzeWithImage(String ocr, byte[] image) {
        return service.analyze(1L, request(new Item("a1", NOW, null, ocr)), java.util.Map.of("a1", image));
    }

    private void givenNewCapture() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
    }

    private static final ClassificationResult OK = new ClassificationResult(Category.INFO, List.of("팁"), "요약");

    @Test
    void 분류기가_이미지를_쓰겠다고_하면_검증_축소해서_함께_분류한다() {
        givenNewCapture();
        when(classifier.imageDecision("짧음")).thenReturn(com.remine.server.classifier.ImageDecision.USE);
        ArgumentCaptor<byte[]> sent = ArgumentCaptor.forClass(byte[].class);
        when(classifier.classify(eq("짧음"), sent.capture())).thenReturn(OK);

        AnalyzeResponse response = analyzeWithImage("짧음", jpeg(3000, 1500));

        assertThat(response.analyzed()).hasSize(1);
        java.awt.image.BufferedImage delivered = decode(sent.getValue());
        assertThat(delivered.getWidth()).isEqualTo(1024); // 긴 변이 1024로 줄었다
        assertThat(delivered.getHeight()).isEqualTo(512);
    }

    @Test
    void 기준값_이상이거나_마스킹된_캡처의_이미지는_분류기에_넘기지_않고_텍스트로_분류한다() {
        givenNewCapture();
        when(classifier.imageDecision("긴 글")).thenReturn(com.remine.server.classifier.ImageDecision.ABOVE_THRESHOLD);
        when(classifier.imageDecision("번호 [전화번호]")).thenReturn(com.remine.server.classifier.ImageDecision.PHONE_MASKED);
        when(classifier.classify(eq("긴 글"), isNull())).thenReturn(OK);
        when(classifier.classify(eq("번호 [전화번호]"), isNull())).thenReturn(OK);

        // 디코딩하지 않으므로 JPEG가 아닌 바이트여도 실패하지 않는다(= 검증조차 하지 않았다)
        byte[] notEvenImage = {1, 2, 3};
        assertThat(analyzeWithImage("긴 글", notEvenImage).failed()).isEmpty();
        assertThat(analyzeWithImage("번호 [전화번호]", notEvenImage).failed()).isEmpty();
    }

    @Test
    void 이미지를_쓰지_않는_분류기면_이미지를_무시한다() {
        givenNewCapture();
        when(classifier.imageDecision("글")).thenReturn(com.remine.server.classifier.ImageDecision.NOT_SUPPORTED);
        when(classifier.classify(eq("글"), isNull())).thenReturn(OK);

        assertThat(analyzeWithImage("글", new byte[]{1}).analyzed()).hasSize(1);
    }

    @Test
    void 장당_최대_크기를_넘으면_그_캡처만_IMAGE_TOO_LARGE로_실패한다() {
        givenNewCapture();
        when(classifier.imageDecision("글")).thenReturn(com.remine.server.classifier.ImageDecision.USE);

        AnalyzeResponse response = analyzeWithImage("글", new byte[1_048_577]);

        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("a1", AnalyzeResponse.Reason.IMAGE_TOO_LARGE));
        verify(classifier, never()).classify(anyString(), any());
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue()).allMatch(Outcome::failed); // 미분석으로 남는다
    }

    @Test
    void JPEG가_아니거나_읽을_수_없으면_IMAGE_INVALID로_실패한다() {
        givenNewCapture();
        when(classifier.imageDecision("글")).thenReturn(com.remine.server.classifier.ImageDecision.USE);

        AnalyzeResponse response = analyzeWithImage("글", new byte[]{1, 2, 3});

        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("a1", AnalyzeResponse.Reason.IMAGE_INVALID));
        verify(classifier, never()).classify(anyString(), any());
    }

    @Test
    void 빈_OCR이어도_쓸_수_있는_이미지가_있으면_분류기로_보낸다() {
        givenNewCapture();
        when(classifier.imageDecision("")).thenReturn(com.remine.server.classifier.ImageDecision.USE);
        when(classifier.classify(eq(""), any(byte[].class))).thenReturn(OK);

        AnalyzeResponse response = analyzeWithImage("", jpeg(100, 100));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::category).containsExactly(Category.INFO);
    }

    @Test
    void 빈_OCR이고_이미지를_쓰지_않으면_분류기를_거치지_않고_기타다() {
        givenNewCapture();
        when(classifier.imageDecision(null)).thenReturn(com.remine.server.classifier.ImageDecision.NOT_SUPPORTED);

        AnalyzeResponse response = service.analyze(1L, request(new Item("a1", NOW, null, null)),
                java.util.Map.of("a1", jpeg(10, 10)));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::category).containsExactly(Category.ETC);
        verify(classifier, never()).classify(anyString(), any());
    }

    @Test
    void 이미_분석된_캡처의_이미지는_판정도_디코딩도_하지_않는다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of("a1"));

        AnalyzeResponse response = analyzeWithImage("글", new byte[]{1});

        assertThat(response.skipped()).containsExactly("a1");
        verify(classifier, never()).imageDecision(any());
    }

    @Test
    void 같은_캡처를_다른_요청이_분석_중이면_한_번만_분석하고_나머지는_IN_PROGRESS다() throws Exception {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        CountDownLatch entered = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        when(classifier.classify("글", null)).thenAnswer(inv -> {
            entered.countDown();
            release.await(5, TimeUnit.SECONDS); // 첫 요청이 분류 중인 상태로 붙잡아 둔다
            return new ClassificationResult(Category.ETC, List.of(), "");
        });
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try {
            Future<AnalyzeResponse> first = pool.submit(() -> service.analyze(1L, request(new Item("a1", NOW, null, "글"))));
            assertThat(entered.await(5, TimeUnit.SECONDS)).isTrue();

            AnalyzeResponse second = service.analyze(1L, request(new Item("a1", NOW, null, "글")));
            release.countDown();

            assertThat(second.failed()).containsExactly(
                    new AnalyzeResponse.Failure("a1", AnalyzeResponse.Reason.IN_PROGRESS));
            assertThat(second.analyzed()).isEmpty();
            assertThat(first.get(5, TimeUnit.SECONDS).analyzed()).hasSize(1);
            verify(classifier, times(1)).classify("글", null);
            verify(persister, times(1)).saveAll(eq(1L), any()); // 두 번째 요청은 저장할 것이 없다
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void 분석_중_예외가_나도_선점을_풀어_다음_요청은_다시_분석한다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("글", null)).thenReturn(new ClassificationResult(Category.ETC, List.of(), ""));
        doThrow(new IllegalStateException("저장 실패")).doNothing().when(persister).saveAll(eq(1L), any());

        assertThatThrownBy(() -> service.analyze(1L, request(new Item("a1", NOW, null, "글"))))
                .isInstanceOf(IllegalStateException.class);
        AnalyzeResponse retry = service.analyze(1L, request(new Item("a1", NOW, null, "글")));

        assertThat(retry.failed()).isEmpty();
        assertThat(retry.analyzed()).hasSize(1);
    }

    @Test
    void 다른_기기의_같은_localAssetId는_막지_않는다() throws Exception {
        when(deviceRepository.findCreatedAtById(any())).thenReturn(Optional.of(REGISTERED));
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
        CountDownLatch entered = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        when(classifier.classify("글", null)).thenAnswer(inv -> {
            if (entered.getCount() > 0) {
                entered.countDown();
                release.await(5, TimeUnit.SECONDS);
            }
            return new ClassificationResult(Category.ETC, List.of(), "");
        });
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try {
            Future<AnalyzeResponse> first = pool.submit(() -> service.analyze(1L, request(new Item("a1", NOW, null, "글"))));
            assertThat(entered.await(5, TimeUnit.SECONDS)).isTrue();

            AnalyzeResponse other = service.analyze(2L, request(new Item("a1", NOW, null, "글")));
            release.countDown();

            assertThat(other.analyzed()).hasSize(1);
            assertThat(first.get(5, TimeUnit.SECONDS).analyzed()).hasSize(1);
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void 요청_마감이_지나면_새_호출을_시작하지_않고_남은_캡처는_DEADLINE_EXCEEDED다() {
        // 마감 0 → 첫 호출 전에 이미 지났다. 이미 분석된 것·글자 없는 것은 LLM이 필요 없어 그대로 처리한다.
        service = service(properties(20, Duration.ZERO), deviceRepository, screenshotRepository, classifier, persister,
                olderQuota);
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of("done"));

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("done", NOW, null, "이미 분석"),
                new Item("blank", NOW, null, ""),
                new Item("a1", NOW, null, "글1"),
                new Item("a2", NOW, null, "글2")));

        assertThat(response.skipped()).containsExactly("done");
        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("blank");
        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("a1", AnalyzeResponse.Reason.DEADLINE_EXCEEDED),
                new AnalyzeResponse.Failure("a2", AnalyzeResponse.Reason.DEADLINE_EXCEEDED));
        verify(classifier, never()).classify(anyString(), any());
    }

    private static java.awt.image.BufferedImage decode(byte[] jpeg) {
        try {
            return javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(jpeg));
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    // ---- 예전 스크린샷(기기 등록 전에 찍힘) 하루 한도 ----

    private static final LocalDateTime OLD = REGISTERED.minusDays(30);
    private static final LocalDate DAY = LocalDate.of(2026, 10, 14);

    private void givenNothingAnalyzed() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of());
    }

    @Test
    void 예전_스크린샷은_예약한_만큼만_분류하고_넘친_장은_LLM_없이_DAILY_LIMIT_EXCEEDED() {
        givenNothingAnalyzed();
        OlderQuota.Reservation reservation = new OlderQuota.Reservation(DAY, DAY.minusDays(1), 2, 1);
        when(olderQuota.reserve(1L, List.of(false, false, false))).thenReturn(reservation);
        when(classifier.classify(anyString(), isNull())).thenReturn(OK);

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("o1", OLD, null, "예전1"), new Item("o2", OLD, null, "예전2"), new Item("o3", OLD, null, "예전3")));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("o1", "o2");
        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("o3", AnalyzeResponse.Reason.DAILY_LIMIT_EXCEEDED));
        verify(classifier, never()).classify(eq("예전3"), any());
        // 넘친 장은 저장하지 않는다(미분석 행도 만들지 않음 → 앱이 내일 다시 보낸다)
        verify(persister).saveAll(eq(1L), outcomes.capture());
        assertThat(outcomes.getValue()).extracting(o -> o.item().localAssetId()).containsExactly("o1", "o2");
        verify(olderQuota).settle(1L, reservation, 0, 0);
    }

    @Test
    void 새_스크린샷은_예약하지_않고_한도와_무관하게_분류한다() {
        givenNothingAnalyzed();
        when(classifier.classify(anyString(), isNull())).thenReturn(OK);

        AnalyzeResponse response = service.analyze(1L, request(
                new Item("n1", REGISTERED.plusHours(1), null, "새1"), new Item("n2", NOW, null, "새2")));

        assertThat(response.analyzed()).hasSize(2);
        verify(olderQuota, never()).reserve(anyLong(), any());
        verify(olderQuota, never()).settle(anyLong(), any(), anyInt(), anyInt());
    }

    @Test
    void 등록_시각보다_먼저_찍힌_캡처만_예전이다() {
        givenNothingAnalyzed();
        when(olderQuota.reserve(eq(1L), any())).thenReturn(new OlderQuota.Reservation(DAY, DAY, 1, 1));
        when(classifier.classify(anyString(), isNull())).thenReturn(OK);

        service.analyze(1L, request(new Item("same", REGISTERED, null, "등록 순간"),
                new Item("before", REGISTERED.minusSeconds(1), null, "1초 전")));

        verify(olderQuota).reserve(1L, List.of(false)); // 1초 전 것만 예전
    }

    @Test
    void 새_것과_예전_것은_따로_분류해_호출_수를_나눠_센다() {
        givenNothingAnalyzed();
        OlderQuota.Reservation reservation = new OlderQuota.Reservation(DAY, DAY, 1, 1);
        when(olderQuota.reserve(1L, List.of(false))).thenReturn(reservation);
        doAnswer(inv -> {
            List<Classifier.Input> inputs = inv.getArgument(0);
            return new Classifier.Counted(inputs.stream().map(i -> new Classifier.Classified(OK, null)).toList(),
                    inputs.get(0).ocrText().startsWith("새") ? 2 : 1);
        }).when(classifier).classifyAllCounted(any(), any());

        AnalyzeResponse response = service.analyze(1L, request(new Item("o1", OLD, null, "예전"),
                new Item("n1", NOW, null, "새")));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("o1", "n1");
        verify(classifier, times(2)).classifyAllCounted(any(), any());
        verify(olderQuota).recordNewCalls(2);
        verify(olderQuota).settle(1L, reservation, 0, 1);
    }

    @Test
    void 예전_장_분류가_실패하면_그_장은_환불하고_서버_예약은_실제_호출_수로_정산한다() {
        givenNothingAnalyzed();
        OlderQuota.Reservation reservation = new OlderQuota.Reservation(DAY, DAY, 2, 1);
        when(olderQuota.reserve(1L, List.of(false, false))).thenReturn(reservation);
        doReturn(new Classifier.Counted(List.of(
                new Classifier.Classified(OK, null),
                new Classifier.Classified(null, new ClassificationException(Reason.INVALID_RESPONSE, "형식 오류"))), 2))
                .when(classifier).classifyAllCounted(any(), any());

        AnalyzeResponse response = service.analyze(1L, request(new Item("o1", OLD, null, "예전1"),
                new Item("o2", OLD, null, "예전2")));

        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("o2", AnalyzeResponse.Reason.LLM_INVALID_RESPONSE));
        verify(olderQuota).settle(1L, reservation, 1, 2); // 1장 환불, 서버는 실제 2번(빠진 장 단건 재시도 포함)
    }

    @Test
    void 쿼터_초과_429로_호출이_실패하면_기기와_서버_예약을_모두_돌려준다() {
        givenNothingAnalyzed();
        OlderQuota.Reservation reservation = new OlderQuota.Reservation(DAY, DAY, 2, 1);
        when(olderQuota.reserve(1L, List.of(false, false))).thenReturn(reservation);
        ClassificationException quota = new ClassificationException(Reason.CALL_FAILED, "HTTP 429 RESOURCE_EXHAUSTED");
        doReturn(new Classifier.Counted(List.of(
                new Classifier.Classified(null, quota), new Classifier.Classified(null, quota)), 0))
                .when(classifier).classifyAllCounted(any(), any());

        AnalyzeResponse response = service.analyze(1L, request(new Item("o1", OLD, null, "예전1"),
                new Item("o2", OLD, null, "예전2")));

        assertThat(response.failed()).extracting(AnalyzeResponse.Failure::reason)
                .containsOnly(AnalyzeResponse.Reason.LLM_CALL_FAILED);
        verify(olderQuota).settle(1L, reservation, 2, 0); // 두 장 모두 환불, 성공한 호출 0번
    }

    @Test
    void 분류가_예외로_끝나도_예전_예약은_전부_돌려준다() {
        givenNothingAnalyzed();
        OlderQuota.Reservation reservation = new OlderQuota.Reservation(DAY, DAY, 1, 1);
        when(olderQuota.reserve(1L, List.of(false))).thenReturn(reservation);
        doThrow(new IllegalStateException("예상 못 한 오류")).when(classifier).classifyAllCounted(any(), any());

        assertThatThrownBy(() -> service.analyze(1L, request(new Item("o1", OLD, null, "예전"))))
                .isInstanceOf(IllegalStateException.class);
        verify(olderQuota).settle(1L, reservation, 1, 0);
    }

    @Test
    void 서버_예전_예산이_다_차면_예전만_멈추고_새_스크린샷은_계속_분류한다() {
        givenNothingAnalyzed();
        when(olderQuota.reserve(1L, List.of(false))).thenReturn(new OlderQuota.Reservation(DAY, DAY, 0, 0));
        when(classifier.classify(anyString(), isNull())).thenReturn(OK);

        AnalyzeResponse response = service.analyze(1L, request(new Item("o1", OLD, null, "예전"),
                new Item("n1", NOW, null, "새")));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::localAssetId).containsExactly("n1");
        assertThat(response.failed()).containsExactly(
                new AnalyzeResponse.Failure("o1", AnalyzeResponse.Reason.DAILY_LIMIT_EXCEEDED));
        verify(classifier, never()).classify(eq("예전"), any());
        verify(olderQuota, never()).settle(anyLong(), any(), anyInt(), anyInt());
    }

    @Test
    void 이미_분석된_예전_장은_예약하지_않는다() {
        givenDevice();
        when(screenshotRepository.findAnalyzedLocalAssetIds(any(), any())).thenReturn(Set.of("o1"));

        AnalyzeResponse response = service.analyze(1L, request(new Item("o1", OLD, null, "예전")));

        assertThat(response.skipped()).containsExactly("o1");
        verify(olderQuota, never()).reserve(anyLong(), any());
    }

    @Test
    void 응답에_오늘_남은_예전_스크린샷_몫을_싣는다() {
        givenNothingAnalyzed();
        when(classifier.classify(anyString(), isNull())).thenReturn(OK);
        when(olderQuota.remainingToday(1L)).thenReturn(120);

        AnalyzeResponse response = service.analyze(1L, request(new Item("n1", NOW, null, "새")));

        assertThat(response.olderRemainingToday()).isEqualTo(120);
    }
}
