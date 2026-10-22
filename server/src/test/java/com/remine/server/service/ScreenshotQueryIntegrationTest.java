package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.dto.AnalyzeRequest;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.dto.CategorySummaryResponse;
import com.remine.server.dto.ScreenshotPageResponse;
import com.remine.server.dto.ScreenshotResponse;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 실제 쿼리(JPQL / 네이티브) 동작과 쿼리 수를 H2로 검증한다.
 * 기기 A에 300장, 기기 B에 5장을 넣는다. 텍스트 7종을 돌려가며 쓰고 마지막 종류는 글자 없음(기타)이다.
 */
// 300장을 한 번에 시드하므로 요청당 최대 항목 수만 올린다 (운영 기본값은 20)
@SpringBootTest(properties = {"spring.jpa.properties.hibernate.generate_statistics=true",
        "remine.analyze.max-batch-size=300"})
class ScreenshotQueryIntegrationTest {

    private static final LocalDateTime BASE = LocalDateTime.of(2026, 10, 1, 0, 0);
    private static final int TOTAL = 300;
    // 인덱스 i % 7 에 해당하는 텍스트 → 카테고리
    private static final String[] TEXTS = {
            "니트 가디건 구매 할인 39,000원",  // 0 SHOPPING  (할인, 원 — "구매"는 불용어라 저장되지 않는다)
            "영화 드라마 시즌2",               // 1 ENTERTAINMENT
            "맛집 카페 영업시간",              // 2 PLACE
            "예약 일정 체크인",                // 3 SCHEDULE
            "ㅋㅋ ㅎㅎ",                      // 4 CHAT
            "방법 꿀팁",                      // 5 INFO
            ""                                // 6 ETC (글자 없음)
    };

    @Autowired ScreenshotService analyzeService;
    @Autowired ScreenshotQueryService queryService;
    @Autowired DeviceRepository deviceRepository;
    @Autowired EntityManagerFactory entityManagerFactory;

    private Long deviceA;
    private Long deviceB;

    @BeforeEach
    void seed() {
        deviceA = deviceRepository.save(new Device("token-a")).getId();
        deviceB = deviceRepository.save(new Device("token-b")).getId();

        List<Item> itemsA = new ArrayList<>();
        for (int i = 0; i < TOTAL; i++) {
            itemsA.add(new Item("a-" + i, BASE.plusMinutes(i), "앱", TEXTS[i % TEXTS.length]));
        }
        analyzeService.analyze(deviceA, new AnalyzeRequest(itemsA));

        List<Item> itemsB = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            itemsB.add(new Item("b-" + i, BASE.plusMinutes(i), "앱", TEXTS[0]));
        }
        analyzeService.analyze(deviceB, new AnalyzeRequest(itemsB));
    }

    @Test
    void 요약은_카테고리별_개수와_대표태그_최신4개를_돌려주고_다른_기기는_섞이지_않는다() {
        CategorySummaryResponse response = queryService.summary(deviceA);

        assertThat(response.categories()).hasSize(Category.values().length);
        CategorySummaryResponse.Item shopping = response.categories().get(Category.SHOPPING.ordinal());
        assertThat(shopping.count()).isEqualTo(countOfKind(0));
        assertThat(shopping.topTags()).containsExactly("원", "할인"); // 빈도 동점 → 이름순
        // 가장 최근 SHOPPING은 i % 7 == 0 인 가장 큰 i들
        int last = lastIndexOfKind(0);
        assertThat(shopping.recentAssetIds())
                .containsExactly("a-" + last, "a-" + (last - 7), "a-" + (last - 14), "a-" + (last - 21));
        assertThat(response.categories().get(Category.ETC.ordinal()).count()).isEqualTo(countOfKind(6));
    }

    @Test
    void 스크린샷이_없는_기기의_요약은_모든_카테고리가_0() {
        Long emptyDevice = deviceRepository.save(new Device("token-empty")).getId();

        CategorySummaryResponse response = queryService.summary(emptyDevice);

        assertThat(response.categories()).hasSize(Category.values().length);
        assertThat(response.categories()).allSatisfy(item -> {
            assertThat(item.count()).isZero();
            assertThat(item.topTags()).isEmpty();
            assertThat(item.recentAssetIds()).isEmpty();
        });
    }

    @Test
    void 목록은_최신순이고_페이지가_나뉘며_다른_기기_데이터는_보이지_않는다() {
        ScreenshotPageResponse page0 = queryService.list(deviceA, null, null, 0, 100);
        ScreenshotPageResponse page3 = queryService.list(deviceA, null, null, 3, 100);

        assertThat(page0.totalElements()).isEqualTo(TOTAL);
        assertThat(page0.totalPages()).isEqualTo(3);
        assertThat(page0.items()).hasSize(100);
        assertThat(page0.items()).extracting(ScreenshotResponse::takenAt)
                .isSortedAccordingTo(Comparator.reverseOrder());
        assertThat(page0.items().get(0).localAssetId()).isEqualTo("a-" + (TOTAL - 1));
        assertThat(page3.items()).isEmpty();
        assertThat(page0.items()).allSatisfy(item -> assertThat(item.localAssetId()).startsWith("a-"));

        assertThat(queryService.list(deviceB, null, null, 0, 30).totalElements()).isEqualTo(5);
    }

    @Test
    void 카테고리와_태그_필터가_동작하고_응답에_태그가_포함된다() {
        ScreenshotPageResponse byCategory = queryService.list(deviceA, Category.SHOPPING, null, 0, 100);
        ScreenshotPageResponse byTag = queryService.list(deviceA, null, "방법", 0, 100);
        ScreenshotPageResponse both = queryService.list(deviceA, Category.PLACE, "할인", 0, 100);

        assertThat(byCategory.totalElements()).isEqualTo(countOfKind(0));
        assertThat(byCategory.items().get(0).tags()).containsExactlyInAnyOrder("할인", "원");
        // 앱의 수정 시트("AI는 X라고 했어요")가 쓰는 값이 목록 응답에도 있다.
        assertThat(byCategory.items()).allSatisfy(item -> {
            assertThat(item.autoCategory()).isNotNull();
            assertThat(item.categorySource()).isNotNull();
        });
        assertThat(byTag.totalElements()).isEqualTo(countOfKind(5));
        assertThat(byTag.items()).allSatisfy(item -> assertThat(item.category()).isEqualTo(Category.INFO));
        assertThat(both.items()).isEmpty();
    }

    @Test
    void 요약_API는_카테고리_수와_무관하게_쿼리_4회_이하() {
        Statistics statistics = statistics();
        statistics.clear();

        queryService.summary(deviceA);

        long count = statistics.getPrepareStatementCount();
        System.out.println("SUMMARY_QUERY_COUNT=" + count);
        assertThat(count).isLessThanOrEqualTo(4); // 기기 확인 1 + 개수 1 + 태그 빈도 1 + 최신 id 1
    }

    @Test
    void 목록_API는_페이지_크기와_무관하게_쿼리_4회_이하() {
        Statistics statistics = statistics();

        for (int size : new int[]{30, 100}) {
            statistics.clear();
            queryService.list(deviceA, null, null, 1, size);
            long count = statistics.getPrepareStatementCount();
            System.out.println("LIST_QUERY_COUNT(size=" + size + ")=" + count);
            assertThat(count).isLessThanOrEqualTo(4); // 기기 확인 1 + 목록 1 + count 1 + 태그 1
        }
    }

    private Statistics statistics() {
        return entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
    }

    private static long countOfKind(int kind) {
        return java.util.stream.IntStream.range(0, TOTAL).filter(i -> i % TEXTS.length == kind).count();
    }

    private static int lastIndexOfKind(int kind) {
        return java.util.stream.IntStream.range(0, TOTAL).filter(i -> i % TEXTS.length == kind).max().orElseThrow();
    }
}
