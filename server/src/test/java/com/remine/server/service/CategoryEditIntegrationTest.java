package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.CategorySource;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.dto.ScreenshotPageResponse;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;

/**
 * 카테고리 수정(F-05)을 실제 DB(H2)로 검증한다: HTTP 계약, 집계 즉시 반영, auto_category 불변,
 * 재분석에서의 USER 값 보호, 쿼리 수. 분류는 기본 fake 분류기(키워드)라 외부 호출은 없다.
 */
@SpringBootTest(properties = "spring.jpa.properties.hibernate.generate_statistics=true")
class CategoryEditIntegrationTest {

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 10, 19, 12, 0);

    private final JsonMapper mapper = JsonMapper.builder().build();
    @Autowired WebApplicationContext context;
    @Autowired ScreenshotService analyzeService;
    @Autowired ScreenshotQueryService queryService;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired JdbcTemplate jdbc;
    @Autowired EntityManagerFactory entityManagerFactory;

    private MockMvc mockMvc;
    private Long deviceId;
    private Long otherDeviceId;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
        deviceId = deviceRepository.save(new Device("a")).getId();
        otherDeviceId = deviceRepository.save(new Device("b")).getId();
    }

    private Screenshot analyze(Long device, String assetId, String ocr) {
        analyzeService.analyze(device, new AnalyzeRequest(List.of(new Item(assetId, NOW, "앱", ocr))));
        return screenshotRepository.findByDeviceAndLocalAssetIds(device, List.of(assetId)).get(0);
    }

    private MockHttpServletResponse patchCategory(Object deviceHeader, Object id, String body) throws Exception {
        var request = patch("/api/screenshots/{id}/category", id)
                .contentType(MediaType.APPLICATION_JSON).content(body.getBytes(StandardCharsets.UTF_8));
        if (deviceHeader != null) {
            request.header("X-Device-Id", String.valueOf(deviceHeader));
        }
        MockHttpServletResponse response = mockMvc.perform(request).andReturn().getResponse();
        response.setCharacterEncoding("UTF-8");
        return response;
    }

    private JsonNode json(MockHttpServletResponse response) throws Exception {
        return mapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }

    @Test
    void 정상_수정은_200과_네_필드를_돌려주고_DB에_반영된다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "니트 가디건 구매 39,000원"); // SHOPPING

        MockHttpServletResponse response = patchCategory(deviceId, s.getId(), "{\"category\":\"PLACE\"}");

        assertThat(response.getStatus()).isEqualTo(200);
        JsonNode body = json(response);
        assertThat(body.path("id").asLong()).isEqualTo(s.getId());
        assertThat(body.path("category").asString()).isEqualTo("PLACE");
        assertThat(body.path("autoCategory").asString()).isEqualTo("SHOPPING");
        assertThat(body.path("categorySource").asString()).isEqualTo("USER");
        Screenshot reloaded = screenshotRepository.findById(s.getId()).orElseThrow();
        assertThat(reloaded.getCategory()).isEqualTo(Category.PLACE);
        assertThat(reloaded.getAutoCategory()).isEqualTo(Category.SHOPPING);
    }

    @Test
    void 같은_값으로_수정하면_USER로_바뀐다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "니트 가디건 구매 39,000원");

        JsonNode body = json(patchCategory(deviceId, s.getId(), "{\"category\":\"SHOPPING\"}"));

        assertThat(body.path("category").asString()).isEqualTo("SHOPPING");
        assertThat(body.path("categorySource").asString()).isEqualTo("USER");
    }

    @Test
    void 잘못된_값은_400과_허용_값_목록() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "구매");

        for (String bad : new String[]{"{\"category\":\"MOVIE_DRAMA\"}", "{\"category\":\"\"}", "{}"}) {
            MockHttpServletResponse response = patchCategory(deviceId, s.getId(), bad);
            assertThat(response.getStatus()).isEqualTo(400);
            JsonNode problem = json(response);
            assertThat(problem.path("allowed")).hasSize(7);
            assertThat(problem.path("allowed").get(0).asString()).isEqualTo("SHOPPING");
        }
        assertThat(screenshotRepository.findById(s.getId()).orElseThrow().getCategorySource())
                .isEqualTo(CategorySource.AUTO);
    }

    @Test
    void 다른_기기의_캡처와_없는_id는_본문까지_똑같은_404다() throws Exception {
        Screenshot others = analyze(otherDeviceId, "x1", "구매");

        MockHttpServletResponse foreign = patchCategory(deviceId, others.getId(), "{\"category\":\"ETC\"}");
        MockHttpServletResponse missing = patchCategory(deviceId, 987654321L, "{\"category\":\"ETC\"}");

        assertThat(foreign.getStatus()).isEqualTo(404);
        assertThat(missing.getStatus()).isEqualTo(404);
        // instance(요청 경로)만 다르고 상태·제목·상세 문구는 같다
        JsonNode f = json(foreign);
        JsonNode m = json(missing);
        assertThat(f.path("detail").asString()).isEqualTo(m.path("detail").asString());
        assertThat(f.path("title").asString()).isEqualTo(m.path("title").asString());
        assertThat(f.path("status").asInt()).isEqualTo(m.path("status").asInt());
        assertThat(f.size()).isEqualTo(m.size());
        // 다른 기기의 값은 바뀌지 않았다
        assertThat(screenshotRepository.findById(others.getId()).orElseThrow().getCategorySource())
                .isEqualTo(CategorySource.AUTO);
    }

    @Test
    void 잘못된_값은_존재_여부와_무관하게_400이다() throws Exception {
        Screenshot others = analyze(otherDeviceId, "x1", "구매");

        // 다른 기기 id든 없는 id든 400 → 400/404 차이로 id의 존재를 알아낼 수 없다
        assertThat(patchCategory(deviceId, others.getId(), "{\"category\":\"NOPE\"}").getStatus()).isEqualTo(400);
        assertThat(patchCategory(deviceId, 987654321L, "{\"category\":\"NOPE\"}").getStatus()).isEqualTo(400);
    }

    @Test
    void 미분석_캡처는_409로_거부한다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "구매");
        jdbc.update("update screenshot set analyzed_at = null where id = ?", s.getId());

        MockHttpServletResponse response = patchCategory(deviceId, s.getId(), "{\"category\":\"ETC\"}");

        assertThat(response.getStatus()).isEqualTo(409);
        assertThat(screenshotRepository.findById(s.getId()).orElseThrow().getCategorySource())
                .isEqualTo(CategorySource.AUTO);
    }

    @Test
    void 기기_헤더가_없으면_400_미등록_기기는_404() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "구매");

        assertThat(patchCategory(null, s.getId(), "{\"category\":\"ETC\"}").getStatus()).isEqualTo(400);
        assertThat(patchCategory(999999L, s.getId(), "{\"category\":\"ETC\"}").getStatus()).isEqualTo(404);
    }

    @Test
    void 수정은_목록과_요약_집계에_즉시_반영되고_태그는_유지된다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "니트 가디건 구매 39,000원"); // SHOPPING, 태그: 원 ("구매"는 불용어)
        List<String> tagsBefore = queryService.list(deviceId, null, null, 0, 30).items().get(0).tags();

        patchCategory(deviceId, s.getId(), "{\"category\":\"INFO\"}");

        ScreenshotPageResponse shopping = queryService.list(deviceId, Category.SHOPPING, null, 0, 30);
        ScreenshotPageResponse info = queryService.list(deviceId, Category.INFO, null, 0, 30);
        assertThat(shopping.totalElements()).isZero();
        assertThat(info.totalElements()).isEqualTo(1);
        assertThat(info.items().get(0).tags()).containsExactlyInAnyOrderElementsOf(tagsBefore).isNotEmpty();

        CategorySummaryResponse summary = queryService.summary(deviceId);
        assertThat(count(summary, Category.SHOPPING)).isZero();
        assertThat(count(summary, Category.INFO)).isEqualTo(1);
        assertThat(summary.categories().stream().filter(i -> i.category() == Category.INFO).findFirst().orElseThrow()
                .recentAssetIds()).containsExactly("a1");
    }

    private static long count(CategorySummaryResponse summary, Category category) {
        return summary.categories().stream().filter(i -> i.category() == category).findFirst().orElseThrow().count();
    }

    @Test
    void 사용자가_정한_값은_같은_캡처를_다시_분석해도_덮어쓰지_않는다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "니트 가디건 구매 39,000원"); // SHOPPING
        patchCategory(deviceId, s.getId(), "{\"category\":\"PLACE\"}");
        // 어떤 경로로든 이 행이 다시 분석 대상이 된 상황(analyzed_at 해제)을 만든다
        jdbc.update("update screenshot set analyzed_at = null where id = ?", s.getId());

        analyzeService.analyze(deviceId, new AnalyzeRequest(List.of(
                new Item("a1", NOW, "앱", "영화 드라마 시즌2")))); // fake 분류기는 ENTERTAINMENT를 낸다

        Screenshot after = screenshotRepository.findById(s.getId()).orElseThrow();
        assertThat(after.getAnalyzedAt()).isNotNull();
        assertThat(after.getCategory()).isEqualTo(Category.PLACE);
        assertThat(after.getCategorySource()).isEqualTo(CategorySource.USER);
        assertThat(after.getAutoCategory()).isEqualTo(Category.SHOPPING);
    }

    @Test
    void 수정_한_번의_쿼리는_조회와_UPDATE_위주로_작다() throws Exception {
        Screenshot s = analyze(deviceId, "a1", "구매");
        Statistics statistics = entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
        statistics.clear();

        assertThat(patchCategory(deviceId, s.getId(), "{\"category\":\"CHAT\"}").getStatus()).isEqualTo(200);

        // 기기 존재 확인 1 + 캡처 조회 1 + UPDATE 1
        assertThat(statistics.getPrepareStatementCount()).isLessThanOrEqualTo(3);
    }
}
