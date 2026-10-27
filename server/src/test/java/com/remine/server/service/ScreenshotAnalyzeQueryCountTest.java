package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** 300장 배치 분석 시 실행되는 SQL(PreparedStatement) 수를 측정한다. */
// 300장을 한 번에 넣어 쿼리 수를 재므로 요청당 최대 항목 수만 올린다 (운영 기본값은 20)
@SpringBootTest(properties = {"spring.jpa.properties.hibernate.generate_statistics=true",
        "remine.analyze.max-batch-size=300"})
class ScreenshotAnalyzeQueryCountTest {

    private static final String[] TEXTS = {
            "니트 가디건 구매 할인 39,000원", "영화 드라마 시즌2", "맛집 카페 영업시간",
            "예약 일정 체크인", "ㅋㅋ ㅎㅎ", "방법 꿀팁"};

    @Autowired ScreenshotService service;
    @Autowired DeviceRepository deviceRepository;
    @Autowired EntityManagerFactory entityManagerFactory;

    @Test
    void 삼백장_배치_분석의_쿼리_수() {
        Device device = deviceRepository.save(new Device("token"));
        List<Item> items = new ArrayList<>();
        for (int i = 0; i < 300; i++) {
            items.add(new Item("asset-" + i, LocalDateTime.now(), null, TEXTS[i % TEXTS.length]));
        }
        Statistics statistics = entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
        statistics.clear();

        service.analyze(device.getId(), new AnalyzeRequest(items));

        long count = statistics.getPrepareStatementCount();
        System.out.println("QUERY_COUNT=" + count);
        // H2: 개선 전 2019회 → 태그 조회·생성을 일괄 처리해 1170회.
        // PostgreSQL + IDENTITY: 916회 — INSERT가 행마다 나가 배치되지 않는다(screenshot 300 + screenshot_tag·tag).
        // PostgreSQL + SEQUENCE(50개씩 할당) + JDBC 배치 50: 29회 — 조회 2 + 시퀀스 nextval + 테이블별 배치 INSERT(19 배치).
        assertThat(count).isLessThan(50);
    }
}
