package com.remine.server.service;

import com.remine.server.TestDevices;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.screenshot.Screenshot;
import com.remine.server.domain.screenshot.ScreenshotRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** OCR 원문은 분류에만 쓰고 DB에 남지 않는다(데이터 최소화, V6). 실제 PostgreSQL로 확인한다. */
@SpringBootTest
class OcrTextNotStoredIntegrationTest {

    // 가짜 분류기는 원문 앞 30자를 요약으로 쓰므로, 표식은 그 뒤에 둔다(요약은 저장 대상이다).
    private static final String MARKER = "원문표식XYZ123";
    private static final String OCR = "니트 가디건 구매 39,000원 무료배송 이번주까지 " + "가".repeat(30) + MARKER;

    @Autowired ScreenshotService analyzeService;
    @Autowired ScreenshotRepository screenshotRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired JdbcTemplate jdbc;

    @Test
    void screenshot_표에_ocr_text_컬럼이_없다() {
        Integer columns = jdbc.queryForObject("""
                select count(*) from information_schema.columns
                where table_schema = current_schema() and table_name = 'screenshot' and column_name = 'ocr_text'
                """, Integer.class);

        assertThat(columns).isZero();
    }

    @Test
    void 분석해도_저장된_행에_원문이_없다() {
        Long deviceId = TestDevices.save(deviceRepository, "ocr");
        analyzeService.analyze(deviceId, new AnalyzeRequest(List.of(new Item("a1", LocalDateTime.of(2026, 10, 19, 12, 0), "앱", OCR))));
        Screenshot s = screenshotRepository.findByDeviceAndLocalAssetIds(deviceId, List.of("a1")).get(0);
        assertThat(s.getCategory()).isEqualTo(Category.SHOPPING); // 원문은 분류에는 쓰였다

        // 행 전체(모든 컬럼)를 글자로 바꿔 표식이 없는지 본다. 태그 표도 함께.
        String row = jdbc.queryForObject("select row_to_json(s)::text from screenshot s where id = ?", String.class, s.getId());
        String tags = jdbc.queryForObject("""
                select coalesce(string_agg(row_to_json(t)::text, ','), '') from tag t
                join screenshot_tag st on st.tag_id = t.id where st.screenshot_id = ?
                """, String.class, s.getId());

        assertThat(row).doesNotContain(MARKER).doesNotContain("ocr_text");
        assertThat(tags).doesNotContain(MARKER);
    }
}
