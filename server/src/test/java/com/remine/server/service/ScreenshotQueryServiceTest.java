package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRow;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotQueryServiceTest {

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @Mock ScreenshotTagRepository screenshotTagRepository;
    @InjectMocks ScreenshotQueryService service;

    @Test
    void 미등록_기기는_예외() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.list(9L, null, null, 0, 30))
                .isInstanceOf(DeviceNotFoundException.class);
        verify(screenshotRepository, never()).search(any(), any(), any(), any());
    }

    @Test
    void 페이지의_태그를_한_번에_조회해_스크린샷별로_묶는다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        Screenshot a = screenshot(10L, "a1");
        Screenshot b = screenshot(11L, "a2");
        when(screenshotRepository.search(eq(1L), eq(Category.SHOPPING), eq("구매"), any()))
                .thenReturn(new PageImpl<>(List.of(a, b), PageRequest.of(0, 30), 2));
        when(screenshotTagRepository.findTagRows(List.of(10L, 11L))).thenReturn(List.of(
                new ScreenshotTagRow(10L, "구매"), new ScreenshotTagRow(10L, "원")));

        ScreenshotPageResponse response = service.list(1L, Category.SHOPPING, "구매", 0, 30);

        assertThat(response.items()).hasSize(2);
        assertThat(response.items().get(0).tags()).containsExactly("구매", "원");
        assertThat(response.items().get(1).tags()).isEmpty();
        assertThat(response.totalElements()).isEqualTo(2);
    }

    @Test
    void 결과가_없으면_태그_조회를_하지_않는다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.search(eq(1L), isNull(), isNull(), any()))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 30), 0));

        ScreenshotPageResponse response = service.list(1L, null, null, 0, 30);

        assertThat(response.items()).isEmpty();
        verify(screenshotTagRepository, never()).findTagRows(any());
    }

    @Test
    void 공백_태그는_필터로_쓰지_않는다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.search(eq(1L), isNull(), isNull(), any()))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 30), 0));

        service.list(1L, null, "  ", 0, 30);

        verify(screenshotRepository).search(eq(1L), isNull(), isNull(), any());
    }

    private Screenshot screenshot(Long id, String assetId) {
        Screenshot s = new Screenshot(null, assetId, LocalDateTime.of(2026, 10, 14, 12, 0), null, "text");
        ReflectionTestUtils.setField(s, "id", id);
        return s;
    }
}
