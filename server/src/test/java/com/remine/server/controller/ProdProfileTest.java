package com.remine.server.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** 운영 프로필은 상태 확인(health)만 공개하고 개발용·내부 엔드포인트는 닫는다. */
@SpringBootTest(properties = "remine.classifier=fake") // prod는 gemini지만 테스트는 실제 API를 부르지 않는다
@AutoConfigureMockMvc
@ActiveProfiles("prod")
class ProdProfileTest {

    @Autowired MockMvc mvc;

    @Test
    void dev_엔드포인트는_404() throws Exception {
        mvc.perform(post("/api/dev/push-test").header("X-Device-Id", 1)).andExpect(status().isNotFound());
        mvc.perform(get("/api/dev/metrics")).andExpect(status().isNotFound());
    }

    @Test
    void actuator는_health만_열리고_상세는_없다() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist())
                .andExpect(jsonPath("$.details").doesNotExist());
        mvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
        mvc.perform(get("/actuator/metrics")).andExpect(status().isNotFound());
    }
}
