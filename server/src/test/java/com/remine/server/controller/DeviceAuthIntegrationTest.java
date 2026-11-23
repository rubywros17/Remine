package com.remine.server.controller;

import com.remine.server.TestDevices;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.device.DeviceToken;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.service.ScreenshotService;
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
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.json.JsonMapper;

import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.function.UnaryOperator;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 기기 인증: 숫자 id·남의 토큰·없는 토큰으로는 어떤 기기 API에도 닿지 않고, 토큰 원문은 DB·로그에 남지 않는다.
 * 피해 기기(victim)는 실제 등록 API로 만들고 데이터를 하나 심어 둔 뒤, 공격 요청 후에도 그대로인지 본다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class DeviceAuthIntegrationTest {

    @Autowired MockMvc mvc;
    @Autowired DeviceRepository deviceRepository;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired ScreenshotService analyzeService;
    @Autowired JdbcTemplate jdbc;

    private final JsonMapper mapper = JsonMapper.builder().build();

    private record Victim(String token, Long id, Screenshot screenshot) {
    }

    private Victim registerVictim() throws Exception {
        String body = mvc.perform(post("/api/devices").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fcmToken\":\"victim-fcm\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.deviceId").doesNotExist()) // 숫자 id는 내보내지 않는다
                .andReturn().getResponse().getContentAsString();
        String token = mapper.readTree(body).path("token").asString();
        Long id = deviceRepository.findByTokenHash(DeviceToken.hash(token)).orElseThrow().getId();
        analyzeService.analyze(id, new AnalyzeRequest(List.of(
                new Item("v1", LocalDateTime.of(2026, 11, 1, 12, 0), "앱", "니트 가디건 구매 39,000원"))));
        Screenshot s = screenshotRepository.findByDeviceAndLocalAssetIds(id, List.of("v1")).getFirst();
        return new Victim(token, id, s);
    }

    /** 기기 API 전부(조회·수정·휴지통·forget·관심사·카테고리·FCM). */
    private List<MockHttpServletRequestBuilder> deviceApis(Victim v) {
        String ids = "{\"assetIds\":[\"v1\"]}";
        return List.of(
                get("/api/screenshots"),
                get("/api/categories/summary"),
                get("/api/categories/accuracy"),
                get("/api/interests"),
                post("/api/screenshots/analyze").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"items\":[{\"localAssetId\":\"x1\",\"takenAt\":\"2026-11-01T12:00:00\",\"ocrText\":\"구매\"}]}"),
                patch("/api/screenshots/" + v.screenshot().getId() + "/category").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"category\":\"ETC\"}"),
                post("/api/screenshots/trash").contentType(MediaType.APPLICATION_JSON).content(ids),
                post("/api/screenshots/restore").contentType(MediaType.APPLICATION_JSON).content(ids),
                post("/api/screenshots/forget").contentType(MediaType.APPLICATION_JSON).content(ids),
                put("/api/devices/me/fcm-token").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fcmToken\":\"attacker-fcm\"}"),
                delete("/api/devices/me/fcm-token"));
    }

    @Test
    void 숫자_id_없는_토큰_틀린_토큰으로는_어떤_기기_API도_401이고_데이터는_그대로다() throws Exception {
        Victim v = registerVictim();
        List<UnaryOperator<MockHttpServletRequestBuilder>> attacks = List.of(
                r -> r,                                                         // 헤더 없음
                r -> r.header("X-Device-Id", v.id()),                           // 예전 방식: 숫자 id
                r -> r.header("Authorization", "Bearer " + v.id()),             // 숫자 id를 토큰 자리에
                r -> r.header("Authorization", "Bearer " + DeviceToken.generate()), // 모르는 토큰
                r -> r.header("Authorization", v.token()),                      // Bearer 없이
                r -> r.header("Authorization", "Bearer " + v.token().substring(1) + "A")); // 한 글자 틀림

        for (UnaryOperator<MockHttpServletRequestBuilder> attack : attacks) {
            for (MockHttpServletRequestBuilder api : deviceApis(v)) {
                mvc.perform(attack.apply(api))
                        .andExpect(status().isUnauthorized())
                        .andExpect(jsonPath("$.code").value("DEVICE_UNAUTHORIZED"));
            }
        }

        Screenshot after = screenshotRepository.findByDeviceAndLocalAssetIds(v.id(), List.of("v1")).getFirst();
        assertThat(after.getCategory()).isEqualTo(Category.SHOPPING);
        assertThat(after.getTrashedAt()).isNull();
        assertThat(screenshotRepository.findByDeviceAndLocalAssetIds(v.id(), List.of("x1"))).isEmpty();
        assertThat(deviceRepository.findById(v.id()).orElseThrow().getFcmToken()).isEqualTo("victim-fcm");
    }

    @Test
    void 남의_토큰으로는_그_기기의_데이터만_보이고_피해_기기의_캡처는_못_바꾼다() throws Exception {
        Victim v = registerVictim();
        Long attacker = TestDevices.save(deviceRepository, "attacker");

        mvc.perform(get("/api/screenshots").header("Authorization", TestDevices.auth(attacker)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items").isEmpty());
        mvc.perform(patch("/api/screenshots/" + v.screenshot().getId() + "/category")
                        .header("Authorization", TestDevices.auth(attacker))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"category\":\"ETC\"}"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/screenshots/trash").header("Authorization", TestDevices.auth(attacker))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"assetIds\":[\"v1\"]}"))
                .andExpect(status().is2xxSuccessful());

        Screenshot after = screenshotRepository.findByDeviceAndLocalAssetIds(v.id(), List.of("v1")).getFirst();
        assertThat(after.getCategory()).isEqualTo(Category.SHOPPING);
        assertThat(after.getTrashedAt()).isNull();
        // 본인 토큰으로는 보인다
        mvc.perform(get("/api/screenshots").header("Authorization", "Bearer " + v.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items[0].localAssetId").value("v1"));
    }

    @Test
    void config의_기기별_값은_토큰이_맞을_때만_채운다() throws Exception {
        Victim v = registerVictim();

        mvc.perform(get("/api/config").header("X-Device-Id", v.id()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.olderRemainingToday").value(nullValue()));
        mvc.perform(get("/api/config").header("Authorization", "Bearer " + DeviceToken.generate()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.olderRemainingToday").value(nullValue()));
        mvc.perform(get("/api/config").header("Authorization", "Bearer " + v.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.olderRemainingToday").isNumber());
    }

    @Test
    void 토큰_원문은_DB와_로그에_없고_해시만_있다(CapturedOutput output) throws Exception {
        Victim v = registerVictim();
        mvc.perform(get("/api/interests").header("Authorization", "Bearer " + v.token())).andExpect(status().isOk());
        mvc.perform(get("/api/interests").header("Authorization", "Bearer " + v.token() + "x"))
                .andExpect(status().isUnauthorized());

        String row = jdbc.queryForObject("select row_to_json(d)::text from device d where id = ?", String.class, v.id());
        assertThat(row).doesNotContain(v.token())
                .contains(HexFormat.of().formatHex(DeviceToken.hash(v.token()))); // bytea는 \x16진수로 나온다
        assertThat(output.getAll()).doesNotContain(v.token());
    }
}
