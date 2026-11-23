package com.remine.server.controller;

import com.remine.server.TestDevices;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.usage.DailyUsageRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.junit.jupiter.api.BeforeEach;

import java.time.Clock;
import java.time.LocalDate;

import static org.hamcrest.Matchers.nullValue;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
class ConfigControllerTest {

    @Autowired WebApplicationContext context;
    @Autowired DeviceRepository deviceRepository;
    @Autowired DailyUsageRepository usage;
    @Autowired Clock clock;
    MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
    }

    @Test
    void 기본_설정값을_헤더_없이_돌려준다() throws Exception {
        mockMvc.perform(get("/api/config"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.imageThresholdChars").value(150))
                .andExpect(jsonPath("$.maxBatchSize").value(20))
                .andExpect(jsonPath("$.imageMaxBytes").value(1048576))
                .andExpect(jsonPath("$.imageMaxLongSide").value(1024))
                .andExpect(jsonPath("$.imageContentType").value("image/jpeg"))
                .andExpect(jsonPath("$.maxRequestBytes").value(12582912))
                .andExpect(jsonPath("$.classifyIntervalMs").value(0)) // 기본은 가짜 분류기라 대기가 없다
                .andExpect(jsonPath("$.dailyOlderLimit").value(300))
                .andExpect(jsonPath("$.olderRemainingToday").value(nullValue()))
                .andExpect(jsonPath("$.olderResetsAt").value(nullValue()));
    }

    @Test
    void 등록된_기기면_오늘_남은_예전_스크린샷_몫과_다음_한국_자정을_준다() throws Exception {
        long deviceId = TestDevices.save(deviceRepository, null);
        usage.addDeviceOlderCount(deviceId, LocalDate.now(clock), 180);
        String nextMidnight = LocalDate.now(clock).plusDays(1) + "T00:00:00+09:00";

        mockMvc.perform(get("/api/config").header("Authorization", TestDevices.auth(deviceId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.olderRemainingToday").value(120))
                .andExpect(jsonPath("$.olderResetsAt").value(nextMidnight));
    }

    @Test
    void 모르는_기기면_404_없이_기기별_값만_비운다() throws Exception {
        mockMvc.perform(get("/api/config").header("Authorization", TestDevices.auth(987654321L)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyOlderLimit").value(300))
                .andExpect(jsonPath("$.olderRemainingToday").value(nullValue()));
    }
}

@SpringBootTest(properties = {"remine.llm.image-threshold-chars=77", "remine.analyze.max-batch-size=5",
        "remine.image.max-bytes=2048", "remine.image.max-long-side=800", "remine.image.max-request-bytes=3000000"})
class ConfigControllerOverrideTest {

    @Autowired WebApplicationContext context;
    MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).build();
    }

    @Test
    void 설정을_바꾸면_응답이_따라간다() throws Exception {
        mockMvc.perform(get("/api/config"))
                .andExpect(jsonPath("$.imageThresholdChars").value(77))
                .andExpect(jsonPath("$.maxBatchSize").value(5))
                .andExpect(jsonPath("$.imageMaxBytes").value(2048))
                .andExpect(jsonPath("$.imageMaxLongSide").value(800))
                .andExpect(jsonPath("$.maxRequestBytes").value(3000000));
    }
}

@SpringBootTest(properties = {"remine.classifier=gemini", "GEMINI_API_KEY=test-key",
        "remine.llm.gemini.min-interval-ms=3000"})
class ConfigControllerGeminiIntervalTest {

    @Autowired WebApplicationContext context;

    @Test
    void 실제_분류기면_호출_간격을_알려준다() throws Exception {
        MockMvcBuilders.webAppContextSetup(context).build().perform(get("/api/config"))
                .andExpect(jsonPath("$.classifyIntervalMs").value(3000));
    }
}
