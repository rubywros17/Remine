package com.remine.server.controller;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** 4xx·5xx는 WARN 한 줄(메서드·경로·상태 코드)로 남고, 쿼리·헤더·본문은 남지 않는다. */
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class ErrorStatusLogFilterTest {

    @Autowired MockMvc mvc;
    @Autowired DeviceRepository deviceRepository;

    @Test
    void 미등록_기기_404는_경로와_상태_코드만_남긴다(CapturedOutput output) throws Exception {
        mvc.perform(get("/api/screenshots").param("tag", "비밀태그").header("X-Device-Id", 987_654))
                .andExpect(status().isNotFound());

        assertThat(output).contains("WARN").contains("GET /api/screenshots → 404");
        assertThat(output.getOut()).doesNotContain("비밀태그").doesNotContain("987654").doesNotContain("tag=");
    }

    @Test
    void 검증_실패_400도_남기고_본문은_남기지_않는다(CapturedOutput output) throws Exception {
        Long id = deviceRepository.save(new Device("token")).getId();

        mvc.perform(post("/api/screenshots/analyze").header("X-Device-Id", id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"screenshots\":[{\"ocrText\":\"OCR비밀원문\"}]}"))
                .andExpect(status().isBadRequest());

        assertThat(output).contains("POST /api/screenshots/analyze → 400");
        assertThat(output.getOut()).doesNotContain("OCR비밀원문");
    }

    @Test
    void 성공_응답은_남기지_않는다(CapturedOutput output) throws Exception {
        mvc.perform(get("/api/config")).andExpect(status().isOk());

        assertThat(output).doesNotContain("GET /api/config →");
    }
}
