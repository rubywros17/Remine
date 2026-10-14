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
@SpringBootTest(properties = "spring.jpa.properties.hibernate.generate_statistics=true")
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
        // 개선 전 2019회 → 태그 조회·생성을 일괄 처리해 1170회.
        // 남은 쿼리는 IDENTITY 키 전략이라 배치되지 않는 INSERT(screenshot 300 + screenshot_tag 850 + tag 17).
        assertThat(count).isLessThan(1200);
    }
}
