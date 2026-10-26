package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.exception.DeviceNotFoundException;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** forget: 앱이 보내지 말았어야 할 캡처(Remine 자기 캡처)를 지우면 관심사 횟수도 바로 줄어든다. */
@SpringBootTest
@AutoConfigureMockMvc
class ScreenshotForgetIntegrationTest {

    @Autowired ScreenshotPersister persister;
    @Autowired ScreenshotForgetService forgetService;
    @Autowired InterestService interestService;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired Clock clock;
    @Autowired MockMvc mvc;

    @Test
    void 이_기기의_그_캡처만_태그_연결과_함께_지우고_관심사_횟수가_줄어든다() {
        LocalDateTime now = LocalDateTime.now(clock);
        Long mine = deviceRepository.save(new Device("t1")).getId();
        Long other = deviceRepository.save(new Device("t2")).getId();
        for (String id : List.of("a1", "a2", "a3", "own1")) {
            save(mine, id, now.minusDays(1), "뜨개질");
        }
        save(other, "own1", now.minusDays(1), "뜨개질");
        assertThat(interestService.detect(mine, now).getFirst().captureCount()).isEqualTo(4);

        int deleted = forgetService.forget(mine, List.of("own1", "없는것"));

        assertThat(deleted).isEqualTo(1);
        assertThat(interestService.detect(mine, now).getFirst().captureCount()).isEqualTo(3);
        assertThat(screenshotRepository.findByDeviceAndLocalAssetIds(other, Set.of("own1"))).hasSize(1);
        assertThat(forgetService.forget(mine, List.of("own1"))).as("다시 보내도 같다").isZero();
    }

    @Test
    void 등록되지_않은_기기는_DeviceNotFound() {
        assertThatThrownBy(() -> forgetService.forget(999_999L, List.of("a")))
                .isInstanceOf(DeviceNotFoundException.class);
    }

    @Test
    void 엔드포인트는_204이고_빈_목록도_204_목록이_없거나_500개를_넘으면_400() throws Exception {
        Long id = deviceRepository.save(new Device("t3")).getId();
        String tooMany = "{\"assetIds\":[" + "\"a\",".repeat(500) + "\"a\"]}";
        for (String body : List.of("{\"assetIds\":[\"a\"]}", "{\"assetIds\":[]}")) {
            mvc.perform(post("/api/screenshots/forget").header("X-Device-Id", id)
                    .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isNoContent());
        }
        for (String body : List.of("{}", tooMany)) {
            mvc.perform(post("/api/screenshots/forget").header("X-Device-Id", id)
                    .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isBadRequest());
        }
    }

    private void save(Long device, String assetId, LocalDateTime at, String tag) {
        persister.saveAll(device, List.of(new Outcome(new Item(assetId, at, "앱", "ocr"),
                new ClassificationResult(Category.SHOPPING, List.of(tag), "요약"))));
    }
}
