package com.remine.server.controller;

import com.remine.server.TestDevices;
import com.remine.server.controller.LegacyDeviceClaim.Reason;
import com.remine.server.controller.LegacyDeviceClaim.Request;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.DeviceToken;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** [임시] {@link LegacyDeviceClaim}과 함께 지운다. */
class LegacyDeviceClaimTest {

    /** 토큰 도입 전에 등록된 기기(token_hash null). */
    static Long legacyDevice(DeviceRepository repository, String fcmToken) {
        return repository.save(new Device(fcmToken)).getId();
    }

    /** 조건별 판단. 실제 DB에서 클래스를 직접 만들어 허용 목록·시각을 테스트마다 정한다. */
    @Nested
    @SpringBootTest
    class 판단 {

        final Clock clock = Clock.fixed(Instant.parse("2026-11-24T00:00:00Z"), ZoneId.of("Asia/Seoul"));

        @Autowired JdbcTemplate jdbc;
        @Autowired DeviceRepository deviceRepository;

        LegacyDeviceClaim claim(Long... ids) {
            String list = Arrays.stream(ids).map(String::valueOf).collect(Collectors.joining(","));
            return new LegacyDeviceClaim(jdbc, clock, list, "2026-11-27T00:00+09:00");
        }

        @Test
        void 조건을_모두_만족하면_한_번만_허용하고_그_토큰으로_찾는다() {
            Long id = legacyDevice(deviceRepository, "fcm-a");
            String token = DeviceToken.generate();

            assertThat(claim(id).decide(new Request(id, "fcm-a"), DeviceToken.hash(token))).isEqualTo(Reason.ALLOWED);
            assertThat(deviceRepository.findByTokenHash(DeviceToken.hash(token))).get()
                    .extracting(Device::getId).isEqualTo(id);
            // 두 번째는 같은 값이어도 거절(먼저 받은 쪽만), 처음 토큰은 그대로
            assertThat(claim(id).decide(new Request(id, "fcm-a"), DeviceToken.hash(DeviceToken.generate())))
                    .isEqualTo(Reason.ALREADY_CLAIMED);
            assertThat(deviceRepository.findByTokenHash(DeviceToken.hash(token))).isPresent();
        }

        @Test
        void 허용_목록_밖_기한_지남_FCM_불일치_FCM_없음_이미_토큰_있음_없는_기기는_거절() {
            Long listed = legacyDevice(deviceRepository, "fcm-b");
            Long unlisted = legacyDevice(deviceRepository, "fcm-c");
            Long noFcm = legacyDevice(deviceRepository, null);
            Long modern = TestDevices.save(deviceRepository, "fcm-d"); // 새 방식으로 등록(토큰 있음)
            LegacyDeviceClaim claim = claim(listed, noFcm, modern, 999_999L);
            byte[] hash = DeviceToken.hash(DeviceToken.generate());

            assertThat(claim.decide(new Request(unlisted, "fcm-c"), hash)).isEqualTo(Reason.NOT_LISTED);
            assertThat(claim.decide(new Request(listed, "fcm-x"), hash)).isEqualTo(Reason.FCM_MISMATCH);
            assertThat(claim.decide(new Request(listed, null), hash)).isEqualTo(Reason.FCM_MISMATCH);
            assertThat(claim.decide(new Request(noFcm, null), hash)).isEqualTo(Reason.NO_FCM);
            assertThat(claim.decide(new Request(modern, "fcm-d"), hash)).isEqualTo(Reason.ALREADY_CLAIMED);
            assertThat(claim.decide(new Request(999_999L, "x"), hash)).isEqualTo(Reason.NOT_FOUND);

            LegacyDeviceClaim expired = new LegacyDeviceClaim(jdbc, clock, String.valueOf(listed), "2026-11-24T09:00+09:00");
            assertThat(expired.decide(new Request(listed, "fcm-b"), hash)).isEqualTo(Reason.EXPIRED);
            // 거절된 기기는 여전히 토큰이 없다
            assertThat(jdbc.queryForObject("select token_hash is null from device where id = ?", Boolean.class, listed))
                    .isTrue();
        }

        @Test
        void 기한_없이_허용_목록만_주면_기동이_실패한다() {
            assertThatThrownBy(() -> new LegacyDeviceClaim(jdbc, clock, "1", " "))
                    .isInstanceOf(IllegalStateException.class);
        }
    }

    /** 설정이 없으면(기본·운영 기본값) 경로 자체가 없다. */
    @Nested
    @SpringBootTest
    @AutoConfigureMockMvc
    class 기본은_꺼짐 {

        @Autowired MockMvc mvc;

        @Test
        void 허용_목록이_없으면_404() throws Exception {
            mvc.perform(post("/api/devices/legacy-claim").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"deviceId\":1,\"fcmToken\":\"x\"}"))
                    .andExpect(status().isNotFound());
        }
    }

    /** HTTP 전체 흐름. 허용 목록에 고정 id가 필요해서 그 id로 행을 직접 넣는다. */
    @Nested
    @SpringBootTest(properties = {"remine.legacy.ids=900001, 900002", "remine.legacy.until=2999-01-01T00:00+09:00"})
    @AutoConfigureMockMvc
    @ExtendWith(OutputCaptureExtension.class)
    class 창구가_열려_있을_때 {

        @Autowired MockMvc mvc;
        @Autowired JdbcTemplate jdbc;

        @AfterEach
        void cleanUp() {
            jdbc.update("delete from device where id in (900001, 900002)");
        }

        @Test
        void 받은_토큰으로_기존_기록에_접근하고_거절은_모두_같은_403이며_로그는_사유_코드뿐(CapturedOutput output)
                throws Exception {
            jdbc.update("insert into device (id, fcm_token, created_at) values (900001, 'secret-fcm-1', now())");

            mvc.perform(post("/api/devices/legacy-claim").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"deviceId\":900001,\"fcmToken\":\"wrong-fcm\"}"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.code").value("LEGACY_CLAIM_REJECTED"));
            mvc.perform(post("/api/devices/legacy-claim").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"deviceId\":900002,\"fcmToken\":\"x\"}"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.code").value("LEGACY_CLAIM_REJECTED"));

            String body = mvc.perform(post("/api/devices/legacy-claim").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"deviceId\":900001,\"fcmToken\":\"secret-fcm-1\"}"))
                    .andExpect(status().isOk())
                    .andReturn().getResponse().getContentAsString();
            String token = JsonMapper.builder().build().readTree(body).path("token").asString();
            assertThat(token).matches("[A-Za-z0-9_-]{43}");

            mvc.perform(get("/api/screenshots").header("Authorization", "Bearer " + token))
                    .andExpect(status().isOk());
            mvc.perform(post("/api/devices/legacy-claim").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"deviceId\":900001,\"fcmToken\":\"secret-fcm-1\"}"))
                    .andExpect(status().isForbidden()); // 한 번만

            assertThat(output.getAll())
                    .contains("legacy claim → FCM_MISMATCH", "legacy claim → NOT_FOUND",
                            "legacy claim → ALLOWED", "legacy claim → ALREADY_CLAIMED")
                    .doesNotContain(token).doesNotContain("secret-fcm-1").doesNotContain("wrong-fcm")
                    .doesNotContain("900001");
        }
    }
}
