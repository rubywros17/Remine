package com.remine.server.service;

import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.exception.DeviceNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotTrashServiceTest {

    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-11-05T03:00:00Z"), SEOUL);

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    ScreenshotTrashService service;

    @BeforeEach
    void setUp() {
        service = new ScreenshotTrashService(deviceRepository, screenshotRepository, CLOCK);
    }

    @Test
    void 휴지통에_넣을_때_시계의_지금을_기록한다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.markTrashed(1L, List.of("a"), LocalDateTime.now(CLOCK))).thenReturn(1);

        assertThat(service.trash(1L, List.of("a"))).isEqualTo(1);
    }

    @Test
    void 되살리면_표시를_지운다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.clearTrashed(1L, List.of("a"))).thenReturn(1);

        assertThat(service.restore(1L, List.of("a"))).isEqualTo(1);
    }

    @Test
    void 빈_목록이면_아무것도_바꾸지_않는다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);

        assertThat(service.trash(1L, List.of())).isZero();
        assertThat(service.restore(1L, List.of())).isZero();
        verifyNoInteractions(screenshotRepository);
    }

    @Test
    void 등록되지_않은_기기는_DeviceNotFound이고_바꾸지_않는다() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.trash(9L, List.of("a"))).isInstanceOf(DeviceNotFoundException.class);
        assertThatThrownBy(() -> service.restore(9L, List.of("a"))).isInstanceOf(DeviceNotFoundException.class);
        verifyNoInteractions(screenshotRepository);
    }
}
