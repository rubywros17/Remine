package com.remine.server.controller;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.push.PushSender;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** 테스트 알림 엔드포인트는 dev 프로필에서만 열린다. */
class DevPushEndpointTest {

    @Nested
    @SpringBootTest
    @AutoConfigureMockMvc
    class 기본_프로필 {
        @Autowired MockMvc mvc;
        @Autowired DeviceRepository deviceRepository;

        @Test
        void 경로가_없어_404() throws Exception {
            Long id = deviceRepository.save(new Device("token")).getId();
            mvc.perform(post("/api/dev/push-test").header("X-Device-Id", id)).andExpect(status().isNotFound());
        }
    }

    @Nested
    @SpringBootTest
    @AutoConfigureMockMvc
    @ActiveProfiles("dev")
    class dev_프로필 {
        @TestConfiguration
        static class Config {
            @Bean
            PushSender pushSender() {
                return (token, message) -> PushSender.Result.SENT;
            }
        }

        @Autowired MockMvc mvc;
        @Autowired DeviceRepository deviceRepository;

        @Test
        void 이_기기에_보내고_결과를_돌려준다() throws Exception {
            Long id = deviceRepository.save(new Device("token")).getId();
            mvc.perform(post("/api/dev/push-test").header("X-Device-Id", id))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.result").value("SENT"));
        }

        @Test
        void 토큰이_없으면_409_미등록_기기는_404() throws Exception {
            Long id = deviceRepository.save(new Device(null)).getId();
            mvc.perform(post("/api/dev/push-test").header("X-Device-Id", id)).andExpect(status().isConflict());
            mvc.perform(post("/api/dev/push-test").header("X-Device-Id", 999_999)).andExpect(status().isNotFound());
        }
    }
}
