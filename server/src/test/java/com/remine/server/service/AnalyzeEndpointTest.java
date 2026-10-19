package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/** analyze HTTP 계약: 요청당 최대 항목 수(기본 20) 초과는 400 + 읽을 수 있는 메시지, 정상은 200 + failed 필드. */
@SpringBootTest
class AnalyzeEndpointTest {

    private final JsonMapper mapper = JsonMapper.builder().build();
    @Autowired WebApplicationContext context;
    @Autowired DeviceRepository deviceRepository;

    private MockMvc mockMvc;
    private Long deviceId;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
        deviceId = deviceRepository.save(new Device("token")).getId();
    }

    private static String body(int count) {
        return "{\"screenshots\":[" + IntStream.rangeClosed(1, count)
                .mapToObj(i -> "{\"localAssetId\":\"id-" + i + "\",\"takenAt\":\"2026-10-19T10:00:00\","
                        + "\"sourceApp\":\"앱\",\"ocrText\":\"니트 가디건 구매 39,000원\"}")
                .collect(Collectors.joining(",")) + "]}";
    }

    private MockHttpServletResponse send(String json, String deviceHeader) throws Exception {
        var request = post("/api/screenshots/analyze")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.getBytes(StandardCharsets.UTF_8));
        if (deviceHeader != null) {
            request.header("X-Device-Id", deviceHeader);
        }
        MockHttpServletResponse response = mockMvc.perform(request).andReturn().getResponse();
        response.setCharacterEncoding("UTF-8");
        return response;
    }

    @Test
    void 최대_항목_수를_넘으면_400과_메시지를_돌려준다() throws Exception {
        MockHttpServletResponse response = send(body(21), String.valueOf(deviceId));

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(response.getContentType()).contains("problem+json");
        JsonNode problem = mapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
        assertThat(problem.path("detail").asString()).contains("최대 20장").contains("21장");
        assertThat(problem.path("max").asInt()).isEqualTo(20);
        assertThat(problem.path("requested").asInt()).isEqualTo(21);
    }

    @Test
    void 최대_항목_수_이하면_정상이고_응답에_failed가_있다() throws Exception {
        MockHttpServletResponse response = send(body(20), String.valueOf(deviceId));

        assertThat(response.getStatus()).isEqualTo(200);
        JsonNode json = mapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
        assertThat(json.path("analyzed").size()).isEqualTo(20);
        assertThat(json.path("skipped").size()).isZero();
        assertThat(json.has("failed")).isTrue();
        assertThat(json.path("failed").size()).isZero(); // fake 분류기는 실패하지 않는다
    }

    @Test
    void 헤더가_없으면_400_미등록_기기는_404() throws Exception {
        assertThat(send(body(1), null).getStatus()).isEqualTo(400);
        assertThat(send(body(1), "999999").getStatus()).isEqualTo(404);
    }
}
