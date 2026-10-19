package com.remine.server.service;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.ThrowableProxyUtil;
import ch.qos.logback.core.read.ListAppender;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * 읽을 수 없는 JSON 본문은 다른 오류와 같은 ProblemDetail 400이고, 본문 내용(OCR 원문 등)이
 * 응답과 로그(DEBUG 포함)에 되풀이되지 않는다.
 */
@SpringBootTest(properties = {"logging.level.org.springframework.web=DEBUG", "logging.level.com.remine=DEBUG"})
class UnreadableBodyTest {

    private static final String MARKER = "OCR-TRACE-MARKER-55aa91";

    private final JsonMapper mapper = JsonMapper.builder().build();
    @Autowired WebApplicationContext context;
    @Autowired DeviceRepository deviceRepository;

    private MockMvc mockMvc;
    private Long deviceId;
    private ListAppender<ILoggingEvent> logs;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
        deviceId = deviceRepository.save(new Device("t")).getId();
        logs = new ListAppender<>();
        logs.start();
        ((Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).addAppender(logs);
    }

    @AfterEach
    void tearDown() {
        ((Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).detachAppender(logs);
        List<String> texts = new ArrayList<>();
        for (ILoggingEvent e : logs.list) {
            texts.add(e.getFormattedMessage()
                    + (e.getThrowableProxy() == null ? "" : ThrowableProxyUtil.asString(e.getThrowableProxy())));
        }
        assertThat(texts).noneMatch(t -> t.contains(MARKER));
    }

    private void assertProblem400(MockHttpServletRequestBuilder request) throws Exception {
        MockHttpServletResponse response = mockMvc.perform(request.header("X-Device-Id", String.valueOf(deviceId))
                .contentType(MediaType.APPLICATION_JSON)).andReturn().getResponse();
        response.setCharacterEncoding("UTF-8");
        String body = response.getContentAsString(StandardCharsets.UTF_8);

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(response.getContentType()).contains("problem+json");
        JsonNode problem = mapper.readTree(body);
        assertThat(problem.path("status").asInt()).isEqualTo(400);
        assertThat(problem.path("title").asString()).isEqualTo("잘못된 요청 본문");
        assertThat(body).doesNotContain(MARKER);
    }

    @Test
    void 문법이_깨진_JSON() throws Exception {
        assertProblem400(post("/api/screenshots/analyze")
                .content(("{\"screenshots\":[{\"ocrText\":\"" + MARKER + "\" 깨짐").getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void 타입이_맞지_않는_값은_그_값을_되풀이하지_않는다() throws Exception {
        assertProblem400(post("/api/screenshots/analyze")
                .content(("{\"screenshots\":[{\"localAssetId\":\"a\",\"takenAt\":\"" + MARKER + "\"}]}")
                        .getBytes(StandardCharsets.UTF_8)));
        assertProblem400(post("/api/screenshots/analyze")
                .content(("{\"screenshots\":\"" + MARKER + "\"}").getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void 본문이_없는_요청() throws Exception {
        assertProblem400(patch("/api/screenshots/1/category"));
    }

    @Test
    void 카테고리_수정_본문이_깨진_경우도_같은_형식이다() throws Exception {
        assertProblem400(patch("/api/screenshots/1/category")
                .content(("{\"category\":" + MARKER).getBytes(StandardCharsets.UTF_8)));
    }
}
