package com.remine.server.service;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.interest.InterestAlert;
import com.remine.server.domain.interest.InterestAlertRepository;
import com.remine.server.domain.screenshot.Category;
import com.remine.server.domain.tag.Tag;
import com.remine.server.domain.tag.TagRepository;
import com.remine.server.dto.AnalyzeRequest.Item;
import com.remine.server.service.ScreenshotPersister.Outcome;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/** 주간 집계를 실제 DB(PostgreSQL)로: 1순위만 PENDING, 같은 주 재실행은 그대로(멱등), 쿨다운 동안 같은 태그는 다음 순위로. */
@SpringBootTest
class InterestAlertServiceTest {

    static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    static final LocalDateTime THURSDAY = LocalDateTime.of(2026, 10, 22, 12, 0);
    static final LocalDate MONDAY = LocalDate.of(2026, 10, 19);

    /** 테스트가 시각을 옮길 수 있는 시계. */
    static class MovableClock extends Clock {
        volatile LocalDateTime now = THURSDAY;

        @Override public ZoneId getZone() { return SEOUL; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now.atZone(SEOUL).toInstant(); }
    }

    @TestConfiguration
    static class Config {
        @Bean
        @Primary
        MovableClock movableClock() {
            return new MovableClock();
        }
    }

    @Autowired MovableClock clock;
    @Autowired InterestAlertService service;
    @Autowired InterestAlertRepository alertRepository;
    @Autowired DeviceRepository deviceRepository;
    @Autowired TagRepository tagRepository;
    @Autowired ScreenshotPersister persister;
    @Autowired InterestPushService pushService;

    private Long deviceId;
    private String prefix; // 테스트끼리 태그가 섞이지 않게

    @BeforeEach
    void setUp() {
        clock.now = THURSDAY;
        deviceId = deviceRepository.save(new Device("token")).getId();
        prefix = UUID.randomUUID().toString().substring(0, 8);
    }

    private void captures(String tag, int count, LocalDateTime at) {
        for (int i = 0; i < count; i++) {
            Item item = new Item(UUID.randomUUID().toString(), at.minusHours(i), "앱", "ocr");
            persister.saveAll(deviceId, List.of(new Outcome(item,
                    new ClassificationResult(Category.SHOPPING, List.of(prefix + tag), "요약"))));
        }
    }

    private Long tagId(String tag) {
        return tagRepository.findAllByNormalizedNameIn(List.of(Tag.keyOf(prefix + tag))).get(0).getId();
    }

    private List<InterestAlert> alerts() {
        return alertRepository.findAll().stream().filter(a -> a.getDevice().getId().equals(deviceId)).toList();
    }

    @Test
    void 기기마다_1순위_관심사_하나만_PENDING으로_저장한다() {
        captures("가디건", 4, THURSDAY);
        captures("드라마", 3, THURSDAY);

        service.createWeeklyAlerts();

        assertThat(alerts()).singleElement().satisfies(a -> {
            assertThat(a.getTag().getId()).isEqualTo(tagId("가디건"));
            assertThat(a.getCaptureCount()).isEqualTo(4);
            assertThat(a.getStatus()).isEqualTo(InterestAlert.Status.PENDING);
            assertThat(a.getWeekStart()).isEqualTo(MONDAY);
            assertThat(a.getSentAt()).isNull();
        });
    }

    @Test
    void 같은_주에_여러_번_돌려도_결과가_같다() {
        captures("가디건", 3, THURSDAY);

        service.createWeeklyAlerts();
        service.createWeeklyAlerts();
        captures("드라마", 5, THURSDAY.plusDays(2)); // 주중에 더 강한 관심사가 생겨도
        clock.now = THURSDAY.plusDays(3);            // 같은 주(일요일)면
        service.createWeeklyAlerts();

        assertThat(alerts()).singleElement()
                .satisfies(a -> assertThat(a.getTag().getId()).isEqualTo(tagId("가디건")));
    }

    @Test
    void 쿨다운_동안_같은_태그는_건너뛰고_다음_순위를_고른다() {
        captures("가디건", 4, THURSDAY);
        captures("드라마", 3, THURSDAY);
        service.createWeeklyAlerts();

        clock.now = THURSDAY.plusWeeks(1);
        captures("가디건", 2, clock.now); // 횟수가 늘어도 예외 없음
        service.createWeeklyAlerts();

        assertThat(alerts()).extracting(a -> a.getTag().getId())
                .containsExactlyInAnyOrder(tagId("가디건"), tagId("드라마"));
    }

    @Test
    void 쿨다운이_지나면_같은_태그를_다시_고를_수_있다() {
        captures("가디건", 3, THURSDAY);
        service.createWeeklyAlerts();

        clock.now = THURSDAY.plusWeeks(3); // 21일 뒤: 아직 쿨다운(28일)
        captures("가디건", 3, clock.now);
        service.createWeeklyAlerts();
        assertThat(alerts()).hasSize(1);

        clock.now = THURSDAY.plusWeeks(4); // 28일 뒤: 다시 가능
        captures("가디건", 3, clock.now);
        service.createWeeklyAlerts();
        assertThat(alerts()).extracting(InterestAlert::getWeekStart)
                .containsExactlyInAnyOrder(MONDAY, MONDAY.plusWeeks(4));
    }

    @Test
    void 관심사가_없는_기기는_만들지_않는다() {
        captures("가디건", 2, THURSDAY);

        service.createWeeklyAlerts();

        assertThat(alerts()).isEmpty();
    }

    @Test
    void 키_파일이_없으면_발송은_꺼지고_PENDING이_그대로다() {
        captures("가디건", 3, THURSDAY);
        service.createWeeklyAlerts();

        pushService.sendPending();

        assertThat(alerts()).singleElement().satisfies(a -> {
            assertThat(a.getStatus()).isEqualTo(InterestAlert.Status.PENDING);
            assertThat(a.getCategory()).isEqualTo(Category.SHOPPING);
        });
    }
}
