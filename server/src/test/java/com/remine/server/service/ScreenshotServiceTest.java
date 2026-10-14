package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.classifier.Classifier;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.tag.Tag;
import com.remine.server.domain.tag.TagRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.AnalyzeResponse;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotServiceTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 14, 12, 0);

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @Mock ScreenshotTagRepository screenshotTagRepository;
    @Mock TagRepository tagRepository;
    @Mock Classifier classifier;
    @InjectMocks ScreenshotService service;

    private final Device device = new Device("token");

    @BeforeEach
    void setUp() {
        lenient().when(deviceRepository.findById(1L)).thenReturn(Optional.of(device));
    }

    @Test
    void 새_스크린샷은_분류해서_저장하고_태그를_연결한다() {
        when(screenshotRepository.findExistingLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("39,000원 구매"))
                .thenReturn(new ClassificationResult(Category.SHOPPING, List.of("구매"), "요약"));
        when(tagRepository.findAllByNameIn(Set.of("구매"))).thenReturn(List.of());
        when(tagRepository.saveAll(any())).thenAnswer(inv -> inv.getArgument(0));

        AnalyzeResponse response = service.analyze(request(new Item("a1", NOW, "쿠팡", "39,000원 구매")));

        assertThat(response.analyzed()).hasSize(1);
        assertThat(response.analyzed().get(0).category()).isEqualTo(Category.SHOPPING);
        assertThat(response.skipped()).isEmpty();
        verify(screenshotRepository).save(any(Screenshot.class));
        verify(screenshotTagRepository).saveAll(any());
    }

    @Test
    void 이미_분석된_localAssetId는_건너뛴다() {
        when(screenshotRepository.findExistingLocalAssetIds(any(), any())).thenReturn(Set.of("a1"));

        AnalyzeResponse response = service.analyze(request(new Item("a1", NOW, null, "구매")));

        assertThat(response.analyzed()).isEmpty();
        assertThat(response.skipped()).containsExactly("a1");
        verify(classifier, never()).classify(any());
        verify(screenshotRepository, never()).save(any());
    }

    @Test
    void 같은_요청_안의_중복_localAssetId도_한_번만_처리한다() {
        when(screenshotRepository.findExistingLocalAssetIds(any(), any())).thenReturn(Set.of());
        when(classifier.classify("글"))
                .thenReturn(new ClassificationResult(Category.ETC, List.of(), "글"));

        AnalyzeResponse response = service.analyze(request(
                new Item("a1", NOW, null, "글"), new Item("a1", NOW, null, "글")));

        assertThat(response.analyzed()).hasSize(1);
        assertThat(response.skipped()).containsExactly("a1");
    }

    @Test
    void 글자_없는_스크린샷은_분류기를_거치지_않고_기타로_저장한다() {
        when(screenshotRepository.findExistingLocalAssetIds(any(), any())).thenReturn(Set.of());

        AnalyzeResponse response = service.analyze(request(
                new Item("a1", NOW, null, "  "), new Item("a2", NOW, null, null)));

        assertThat(response.analyzed()).extracting(AnalyzeResponse.Result::category)
                .containsExactly(Category.ETC, Category.ETC);
        verify(classifier, never()).classify(any());
    }

    @Test
    void 등록되지_않은_기기면_예외() {
        AnalyzeRequest request = new AnalyzeRequest(99L, List.of(new Item("a1", NOW, null, "x")));

        assertThatThrownBy(() -> service.analyze(request)).isInstanceOf(DeviceNotFoundException.class);
    }

    private AnalyzeRequest request(Item... items) {
        return new AnalyzeRequest(1L, List.of(items));
    }
}
