package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/** 실제 DB(H2)와 HTTP로: 14일 경계, 사용자 수정 반영, 다른 기기 분리, 응답에 OCR 원문 없음. */
@SpringBootTest
class InterestIntegrationTest {

    static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 22, 12, 0);
    static final String SECRET_OCR = "비밀 OCR 원문 010-1234";

    @TestConfiguration
    static class FixedClock {
        @Bean
        @Primary
        Clock fixedClock() {
            ZoneId seoul = ZoneId.of("Asia/Seoul");
            return Clock.fixed(NOW.atZone(seoul).toInstant(), seoul);
        }
    }

    @Autowired WebApplicationContext context;
    @Autowired DeviceRepository deviceRepository;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired ScreenshotPersister persister;

    private final JsonMapper mapper = JsonMapper.builder().build();
    private MockMvc mockMvc;
    private Long deviceId;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
        deviceId = deviceRepository.save(new Device("token")).getId();
    }

    private void capture(Long device, String assetId, LocalDateTime takenAt, String... tags) {
        persister.saveAll(device, List.of(new Outcome(new Item(assetId, takenAt, "앱", SECRET_OCR),
                new ClassificationResult(Category.SHOPPING, List.of(tags), "요약"))));
    }

    private JsonNode interests(Long device) throws Exception {
        MockHttpServletResponse response = mockMvc.perform(get("/api/interests").header("X-Device-Id", device))
                .andReturn().getResponse();
        response.setCharacterEncoding("UTF-8");
        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getContentAsString()).doesNotContain(SECRET_OCR).doesNotContain("요약");
        return mapper.readTree(response.getContentAsString()).get("items");
    }

    @Test
    void 십사일_안의_캡처만_세고_사용자_수정_카테고리를_대표로_쓴다() throws Exception {
        capture(deviceId, "in-1", NOW.minusDays(1), "경계 가디건");
        capture(deviceId, "in-2", NOW.minusDays(13), "경계가디건"); // 표기만 다른 같은 태그
        capture(deviceId, "edge", NOW.minusDays(14), "경계 가디건"); // 정확히 14일 전 = 포함
        capture(deviceId, "out", NOW.minusDays(15), "경계 가디건"); // 기간 밖
        capture(deviceId, "two-1", NOW.minusDays(1), "두번뿐");
        capture(deviceId, "two-2", NOW.minusDays(2), "두번뿐");
        for (String assetId : List.of("in-1", "in-2")) {
            Screenshot s = screenshotRepository.findByDeviceAndLocalAssetIds(deviceId, List.of(assetId)).get(0);
            s.changeCategoryByUser(Category.INFO);
            screenshotRepository.save(s);
        }

        JsonNode items = interests(deviceId);

        assertThat(items).hasSize(1);
        JsonNode item = items.get(0);
        assertThat(item.get("tag").asString()).isEqualTo("경계 가디건");
        assertThat(item.get("captureCount").asInt()).isEqualTo(3);
        assertThat(item.get("category").asString()).isEqualTo("INFO");
        assertThat(item.get("dormantDays").asInt()).isEqualTo(1);
        assertThat(item.get("recent").get(0).get("localAssetId").asString()).isEqualTo("in-1");
    }

    @Test
    void 다른_기기의_캡처는_섞이지_않는다() throws Exception {
        Long other = deviceRepository.save(new Device("other")).getId();
        capture(deviceId, "mine-1", NOW.minusDays(1), "기기분리");
        capture(other, "theirs-1", NOW.minusDays(1), "기기분리");
        capture(other, "theirs-2", NOW.minusDays(2), "기기분리");
        capture(other, "theirs-3", NOW.minusDays(3), "기기분리");

        assertThat(interests(deviceId)).isEmpty();
        assertThat(interests(other)).hasSize(1);
        assertThat(interests(other).get(0).get("captureCount").asInt()).isEqualTo(3);
    }

    @Test
    void 미등록_기기는_404() throws Exception {
        assertThat(mockMvc.perform(get("/api/interests").header("X-Device-Id", 999_999L))
                .andReturn().getResponse().getStatus()).isEqualTo(404);
    }
}
