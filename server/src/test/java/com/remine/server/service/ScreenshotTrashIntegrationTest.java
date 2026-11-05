package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest.Item;
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

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** 앱 휴지통: 관심사 집계에서 빠지고 되살리면 돌아온다. 행과 목록은 그대로다. */
@SpringBootTest
@AutoConfigureMockMvc
class ScreenshotTrashIntegrationTest {

    @Autowired ScreenshotPersister persister;
    @Autowired ScreenshotTrashService trashService;
    @Autowired InterestService interestService;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired Clock clock;
    @Autowired MockMvc mvc;

    @Test
    void 휴지통에_넣으면_관심사에서_빠지고_되살리면_돌아온다() {
        LocalDateTime now = LocalDateTime.now(clock);
        Long device = deviceRepository.save(new Device("trash1")).getId();
        for (String id : List.of("a1", "a2", "a3", "a4")) {
            save(device, id, now.minusDays(1), "뜨개질");
        }
        assertThat(count(device, now)).isEqualTo(4);

        assertThat(trashService.trash(device, List.of("a1"))).isEqualTo(1);
        assertThat(count(device, now)).isEqualTo(3);

        // 기준(3회) 아래로 내려가면 관심사(= 푸시 대상) 자체가 사라진다
        trashService.trash(device, List.of("a2"));
        assertThat(interestService.detect(device, now)).isEmpty();

        assertThat(trashService.restore(device, List.of("a1", "a2"))).isEqualTo(2);
        assertThat(count(device, now)).isEqualTo(4);
    }

    @Test
    void 다른_기기의_같은_캡처는_바뀌지_않는다() {
        LocalDateTime now = LocalDateTime.now(clock);
        Long mine = deviceRepository.save(new Device("trash2")).getId();
        Long other = deviceRepository.save(new Device("trash3")).getId();
        for (String id : List.of("b1", "b2", "b3")) {
            save(mine, id, now.minusDays(1), "캠핑");
            save(other, id, now.minusDays(1), "캠핑");
        }

        trashService.trash(mine, List.of("b1"));

        assertThat(interestService.detect(mine, now)).isEmpty();
        assertThat(count(other, now)).isEqualTo(3);
    }

    @Test
    void 다시_보내도_결과가_같고_없는_id는_무시한다() {
        LocalDateTime now = LocalDateTime.now(clock);
        Long device = deviceRepository.save(new Device("trash4")).getId();
        save(device, "c1", now.minusDays(1), "등산");

        assertThat(trashService.trash(device, List.of("c1", "없음"))).isEqualTo(1);
        assertThat(trashService.trash(device, List.of("c1"))).isZero();
        assertThat(trashService.restore(device, List.of("c1", "없음"))).isEqualTo(1);
        assertThat(trashService.restore(device, List.of("c1"))).isZero();
    }

    @Test
    void 휴지통에_있어도_분석된_캡처로_남아_다시_보내면_재분석하지_않는다() {
        LocalDateTime now = LocalDateTime.now(clock);
        Long device = deviceRepository.save(new Device("trash5")).getId();
        save(device, "d1", now.minusDays(1), "요리");

        trashService.trash(device, List.of("d1"));

        assertThat(screenshotRepository.findAnalyzedLocalAssetIds(device, List.of("d1"))).containsExactly("d1");
    }

    @Test
    void 엔드포인트는_204이고_목록이_없거나_500개를_넘으면_400() throws Exception {
        Long id = deviceRepository.save(new Device("trash6")).getId();
        String tooMany = "{\"assetIds\":[" + "\"a\",".repeat(500) + "\"a\"]}";
        for (String path : List.of("/api/screenshots/trash", "/api/screenshots/restore")) {
            mvc.perform(post(path).header("X-Device-Id", id)
                    .contentType(MediaType.APPLICATION_JSON).content("{\"assetIds\":[\"a\"]}"))
                    .andExpect(status().isNoContent());
            for (String body : List.of("{}", tooMany)) {
                mvc.perform(post(path).header("X-Device-Id", id)
                        .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isBadRequest());
            }
        }
    }

    private int count(Long device, LocalDateTime now) {
        return interestService.detect(device, now).getFirst().captureCount();
    }

    private void save(Long device, String assetId, LocalDateTime at, String tag) {
        persister.saveAll(device, List.of(new Outcome(new Item(assetId, at, "앱", "ocr"),
                new ClassificationResult(Category.SHOPPING, List.of(tag), "요약"))));
    }
}
