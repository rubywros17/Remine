package com.remine.server.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.junit.jupiter.api.BeforeEach;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
class ConfigControllerTest {

    @Autowired WebApplicationContext context;
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
                .andExpect(jsonPath("$.maxRequestBytes").value(12582912));
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
