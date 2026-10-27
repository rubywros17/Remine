package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.domain.screenshot.ScreenshotTagRepository;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotForgetServiceTest {

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @Mock ScreenshotTagRepository screenshotTagRepository;
    @InjectMocks ScreenshotForgetService service;

    @Test
    void 태그_연결을_먼저_지우고_캡처를_지운다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.deleteByDeviceAndAssetIds(1L, List.of("a"))).thenReturn(1);

        assertThat(service.forget(1L, List.of("a"))).isEqualTo(1);

        InOrder order = inOrder(screenshotTagRepository, screenshotRepository);
        order.verify(screenshotTagRepository).deleteByDeviceAndAssetIds(1L, List.of("a"));
        order.verify(screenshotRepository).deleteByDeviceAndAssetIds(1L, List.of("a"));
    }

    @Test
    void 빈_목록이면_아무것도_지우지_않는다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);

        assertThat(service.forget(1L, List.of())).isZero();
        verifyNoInteractions(screenshotRepository, screenshotTagRepository);
    }

    @Test
    void 등록되지_않은_기기는_DeviceNotFound이고_지우지_않는다() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.forget(9L, List.of("a"))).isInstanceOf(DeviceNotFoundException.class);
        verifyNoInteractions(screenshotRepository, screenshotTagRepository);
    }
}
