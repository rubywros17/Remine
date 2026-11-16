package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.service.ScreenshotPersister.Outcome;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
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
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/** 실제 DB(PostgreSQL)와 HTTP로: 전체 기간·30일 상태 경계, 넓은 태그 제외, 사용자 수정 반영, 다른 기기 분리, OCR 원문 없음, 쿼리 수. */
@SpringBootTest(properties = "spring.jpa.properties.hibernate.generate_statistics=true")
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
    @Autowired EntityManagerFactory entityManagerFactory;

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
    void 전체_기간을_세고_사용자_수정_카테고리를_대표로_쓴다() throws Exception {
        capture(deviceId, "in-1", NOW.minusDays(1), "경계 가디건");
        capture(deviceId, "in-2", NOW.minusDays(13), "경계가디건"); // 표기만 다른 같은 태그
        capture(deviceId, "old", NOW.minusDays(200), "경계 가디건"); // 오래전 캡처도 센다
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
        assertThat(item.get("status").asString()).isEqualTo("RECENT");
        assertThat(item.get("captureCount").asInt()).isEqualTo(3);
        assertThat(item.get("category").asString()).isEqualTo("INFO");
        assertThat(item.get("dormantDays").asInt()).isEqualTo(1);
        assertThat(item.get("recent").get(0).get("localAssetId").asString()).isEqualTo("in-1");
        assertThat(item.get("recent").get(0).get("takenAt").asString()).startsWith("2026-10-21");
    }

    @Test
    void 잊고_있었던_관심사가_먼저고_넓은_태그는_빠진다_쿼리는_두_번() throws Exception {
        for (int i = 0; i < 5; i++) {
            capture(deviceId, "recent-" + i, NOW.minusDays(1 + i), "요즘네일");
            capture(deviceId, "broad-" + i, NOW.minusDays(1 + i), "패션"); // 설정의 넓은 태그
        }
        capture(deviceId, "old-1", NOW.minusDays(31), "코바늘도안"); // 9/21: 30일 경계를 막 넘음
        capture(deviceId, "old-2", NOW.minusDays(40), "코바늘도안");
        capture(deviceId, "old-3", NOW.minusDays(80), "코바늘도안");
        Statistics statistics = entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
        statistics.clear();

        JsonNode items = interests(deviceId);

        assertThat(statistics.getPrepareStatementCount()).isEqualTo(2); // 기기 확인 + 행 조회
        assertThat(items).extracting(i -> i.get("tag").asString()).containsExactly("코바늘도안", "요즘네일");
        JsonNode forgotten = items.get(0);
        assertThat(forgotten.get("status").asString()).isEqualTo("FORGOTTEN");
        assertThat(forgotten.get("dormantDays").asInt()).isEqualTo(31);
        assertThat(forgotten.get("peakMonth").asInt()).isEqualTo(9);
        assertThat(forgotten.get("peakMonthCount").asInt()).isEqualTo(2);
    }

    /** 옛 앱이 읽던 모양(windowDays 필수, 모르는 필드는 무시). */
    record OldResponse(int windowDays, int minCount, List<OldItem> items) {
    }

    record OldItem(String tag, String category, int captureCount, int dormantDays, List<OldCapture> recent,
                   List<String> linkedTags) {
    }

    record OldCapture(long id, String localAssetId) {
    }

    @Test
    void 옛_앱_응답_형태로도_읽힌다_windowDays_포함() throws Exception {
        for (int i = 0; i < 3; i++) {
            capture(deviceId, "old-app-" + i, NOW.minusDays(40 + i), "옛앱호환");
        }
        MockHttpServletResponse response = mockMvc.perform(get("/api/interests").header("X-Device-Id", deviceId))
                .andReturn().getResponse();
        response.setCharacterEncoding("UTF-8");

        OldResponse old = JsonMapper.builder()
                .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                .enable(DeserializationFeature.FAIL_ON_NULL_CREATOR_PROPERTIES)
                .enable(DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES)
                .build()
                .readValue(response.getContentAsString(), OldResponse.class);

        assertThat(old.windowDays()).isEqualTo(30);
        assertThat(old.minCount()).isEqualTo(3);
        assertThat(old.items()).singleElement().satisfies(item -> {
            assertThat(item.tag()).isEqualTo("옛앱호환");
            assertThat(item.captureCount()).isEqualTo(3);
            assertThat(item.dormantDays()).isEqualTo(40);
            assertThat(item.recent()).extracting(OldCapture::localAssetId).containsExactly("old-app-0", "old-app-1", "old-app-2");
            assertThat(item.linkedTags()).isEmpty();
        });
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
