package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.CategorySource;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.CategoryUpdateResponse;
import com.remine.server.exception.CategoryNotAllowedException;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.exception.ScreenshotNotAnalyzedException;
import com.remine.server.exception.ScreenshotNotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ScreenshotCategoryServiceTest {

    @Mock DeviceRepository deviceRepository;
    @Mock ScreenshotRepository screenshotRepository;
    @InjectMocks ScreenshotCategoryService service;

    private Screenshot analyzed(Category auto) {
        Screenshot s = new Screenshot(new Device("t"), "a1", LocalDateTime.now(), "앱", "글");
        s.applyAnalysis(auto, "요약");
        return s;
    }

    @Test
    void 정상_수정은_category와_USER를_돌려주고_autoCategory는_그대로다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.findByIdAndDeviceId(5L, 1L)).thenReturn(Optional.of(analyzed(Category.SHOPPING)));

        CategoryUpdateResponse response = service.updateCategory(1L, 5L, "PLACE");

        assertThat(response.category()).isEqualTo(Category.PLACE);
        assertThat(response.autoCategory()).isEqualTo(Category.SHOPPING);
        assertThat(response.categorySource()).isEqualTo(CategorySource.USER);
    }

    @Test
    void 같은_값으로_수정해도_USER가_된다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.findByIdAndDeviceId(5L, 1L)).thenReturn(Optional.of(analyzed(Category.INFO)));

        CategoryUpdateResponse response = service.updateCategory(1L, 5L, "INFO");

        assertThat(response.category()).isEqualTo(Category.INFO);
        assertThat(response.categorySource()).isEqualTo(CategorySource.USER);
    }

    @Test
    void 잘못된_값이면_허용_값_목록과_함께_예외이고_아무것도_조회하지_않는다() {
        for (String bad : new String[]{null, "", "shopping", "MOVIE_DRAMA"}) {
            assertThatThrownBy(() -> service.updateCategory(1L, 5L, bad))
                    .isInstanceOfSatisfying(CategoryNotAllowedException.class, e -> {
                        assertThat(e.allowed()).containsExactly("SHOPPING", "ENTERTAINMENT", "PLACE", "INFO",
                                "CHAT", "SCHEDULE", "ETC");
                        assertThat(e.getMessage()).contains("SHOPPING", "ETC");
                    });
        }
        verifyNoInteractions(deviceRepository, screenshotRepository);
    }

    @Test
    void 등록되지_않은_기기는_DeviceNotFound() {
        when(deviceRepository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.updateCategory(9L, 5L, "ETC")).isInstanceOf(DeviceNotFoundException.class);
    }

    @Test
    void 없는_id와_다른_기기의_캡처는_같은_예외다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        when(screenshotRepository.findByIdAndDeviceId(5L, 1L)).thenReturn(Optional.empty());
        when(screenshotRepository.findByIdAndDeviceId(6L, 1L)).thenReturn(Optional.empty());

        Throwable missing = org.assertj.core.api.Assertions.catchThrowable(() -> service.updateCategory(1L, 5L, "ETC"));
        Throwable otherDevices = org.assertj.core.api.Assertions.catchThrowable(() -> service.updateCategory(1L, 6L, "ETC"));

        assertThat(missing).isInstanceOf(ScreenshotNotFoundException.class);
        assertThat(otherDevices).isInstanceOf(ScreenshotNotFoundException.class).hasMessage(missing.getMessage());
    }

    @Test
    void 분석되지_않은_캡처는_수정할_수_없다() {
        when(deviceRepository.existsById(1L)).thenReturn(true);
        Screenshot unanalyzed = new Screenshot(new Device("t"), "a1", LocalDateTime.now(), "앱", "글");
        when(screenshotRepository.findByIdAndDeviceId(5L, 1L)).thenReturn(Optional.of(unanalyzed));

        assertThatThrownBy(() -> service.updateCategory(1L, 5L, "ETC")).isInstanceOf(ScreenshotNotAnalyzedException.class);
        assertThat(unanalyzed.getCategorySource()).isNull();
    }
}
