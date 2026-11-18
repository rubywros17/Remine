package com.remine.server.service;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import com.remine.server.domain.usage.DailyUsageRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.simple.JdbcClient;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 예전 스크린샷 하루 한도를 실제 DB(PostgreSQL)로 검증한다: 원자적 예약·부분 허용·환불, 기기 몫은 한국 시간,
 * 서버 호출 예산은 태평양 시간 날짜로 따로 센다. 한도는 작게(기기 10장, 예산 10회 중 예전 7회) 둔다.
 * 서버 예산 행은 전역이라 다른 테스트와 겹치지 않게 2030년 날짜만 쓰고 테스트마다 지운다.
 */
@SpringBootTest(properties = {"remine.analyze.daily-older-limit=10", "remine.analyze.daily-llm-call-budget=10",
        "remine.analyze.older-call-share-percent=70"})
class OlderQuotaTest {

    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    /** 11월(태평양 표준시 PST, UTC-8): 한국 17:00 = 태평양 자정. */
    private static final LocalDateTime BEFORE_LA_MIDNIGHT = LocalDateTime.of(2030, 11, 20, 16, 59);
    private static final LocalDateTime AFTER_LA_MIDNIGHT = LocalDateTime.of(2030, 11, 20, 17, 1);

    static class MovableClock extends Clock {
        volatile LocalDateTime now = LocalDateTime.of(2030, 11, 20, 12, 0);

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
    @Autowired OlderQuota quota;
    @Autowired DailyUsageRepository usage;
    @Autowired DeviceRepository deviceRepository;
    @Autowired JdbcClient jdbc;

    @BeforeEach
    void setUp() {
        clock.now = LocalDateTime.of(2030, 11, 20, 12, 0);
        jdbc.sql("delete from llm_daily_usage where usage_date >= date '2030-01-01'").update();
    }

    private long newDevice() {
        return deviceRepository.save(new Device(null)).getId();
    }

    private static List<Boolean> texts(int n) {
        return Collections.nCopies(n, false);
    }

    private static List<Boolean> images(int n) {
        return Collections.nCopies(n, true);
    }

    private static LocalDate kst(LocalDateTime t) {
        return t.toLocalDate();
    }

    private static LocalDate la(LocalDateTime kst) {
        return LocalDate.ofInstant(kst.atZone(SEOUL).toInstant(), ZoneId.of("America/Los_Angeles"));
    }

    @Test
    void 기기_한도를_넘으면_남은_만큼만_예약한다() {
        long device = newDevice();

        OlderQuota.Reservation first = quota.reserve(device, texts(6));
        OlderQuota.Reservation second = quota.reserve(device, texts(6));
        OlderQuota.Reservation third = quota.reserve(device, texts(1));

        assertThat(first.items()).isEqualTo(6);
        assertThat(first.calls()).isEqualTo(1);       // 텍스트 6장 = 10장 묶음 1번
        assertThat(second.items()).isEqualTo(4);      // 10장 중 남은 4장만
        assertThat(third.items()).isZero();
        assertThat(usage.deviceOlderCount(device, kst(clock.now))).isEqualTo(10);
        assertThat(quota.remainingToday(device)).isZero();
    }

    @Test
    void 이미지는_5장씩_묶어_호출_수를_잡는다() {
        assertThat(quota.estimateCalls(List.of(true, true, true, true, true, true, false))).isEqualTo(3);
    }

    @Test
    void 서버_예전_몫_70퍼센트에_닿으면_예전은_0이고_새_스크린샷_호출은_기록만_한다() {
        // 예전 몫 7회: 이미지 10장(2회)씩 세 기기 = 6회, 네 번째 기기는 남은 1회 = 5장만
        for (int i = 0; i < 3; i++) {
            assertThat(quota.reserve(newDevice(), images(10)).items()).isEqualTo(10);
        }
        assertThat(quota.reserve(newDevice(), images(10)).items()).isEqualTo(5);
        long late = newDevice();
        assertThat(quota.reserve(late, texts(1)).items()).isZero();
        assertThat(quota.remainingToday(late)).isZero(); // 기기 몫은 10장 남아도 서버 몫이 없다

        quota.recordNewCalls(3); // 새 스크린샷은 막지 않는다

        DailyUsageRepository.LlmCalls calls = usage.llmCalls(la(clock.now));
        assertThat(calls.older()).isEqualTo(7);
        assertThat(calls.newer()).isEqualTo(3);
    }

    @Test
    void 새_스크린샷이_예산을_많이_쓰면_예전_몫도_그만큼_줄어든다() {
        quota.recordNewCalls(9); // 예산 10회 중 9회

        assertThat(quota.reserve(newDevice(), images(10)).items()).isEqualTo(5); // 남은 1회 = 이미지 5장
        assertThat(quota.reserve(newDevice(), texts(1)).items()).isZero();
    }

    @Test
    void 정산하면_실패한_장과_쓰지_않은_호출을_돌려준다() {
        long device = newDevice();
        OlderQuota.Reservation r = quota.reserve(device, texts(3));

        quota.settle(device, r, 2, 0); // 429로 호출이 거절돼 두 장 실패, 성공한 호출 0번

        assertThat(usage.deviceOlderCount(device, kst(clock.now))).isEqualTo(1);
        assertThat(usage.llmCalls(la(clock.now)).older()).isZero();
        assertThat(quota.remainingToday(device)).isEqualTo(9);
    }

    @Test
    void 실제_호출이_예상보다_많으면_그만큼_더_센다() {
        long device = newDevice();
        OlderQuota.Reservation r = quota.reserve(device, texts(3)); // 예상 1회

        quota.settle(device, r, 0, 3); // 빠진 장 단건 재시도로 실제 3회

        assertThat(usage.llmCalls(la(clock.now)).older()).isEqualTo(3);
    }

    @Test
    void 한국_시간_자정이_지나면_기기_몫이_다시_찬다() {
        long device = newDevice();
        clock.now = LocalDateTime.of(2030, 11, 20, 23, 59);
        assertThat(quota.reserve(device, texts(10)).items()).isEqualTo(10);
        assertThat(quota.reserve(device, texts(1)).items()).isZero();

        clock.now = LocalDateTime.of(2030, 11, 21, 0, 1);

        assertThat(quota.reserve(device, texts(10)).items()).isEqualTo(10);
        assertThat(quota.resetsAt()).isEqualTo(OffsetDateTime.of(2030, 11, 22, 0, 0, 0, 0, ZoneOffset.ofHours(9)));
    }

    @Test
    void 한국으로는_같은_날이어도_태평양_자정이_지나면_서버_예산만_새로_센다() {
        clock.now = BEFORE_LA_MIDNIGHT;
        long first = newDevice();
        assertThat(quota.reserve(first, texts(10)).items()).isEqualTo(10);
        for (int i = 0; i < 3; i++) {
            quota.reserve(newDevice(), images(10)); // 2회씩 6회 → 예전 몫 7회 다 씀
        }
        long waiting = newDevice();
        assertThat(quota.reserve(waiting, texts(1)).items()).isZero();

        clock.now = AFTER_LA_MIDNIGHT; // 한국 11/20 17:01 = 태평양 11/20 00:01

        assertThat(kst(AFTER_LA_MIDNIGHT)).isEqualTo(kst(BEFORE_LA_MIDNIGHT));
        assertThat(la(AFTER_LA_MIDNIGHT)).isEqualTo(la(BEFORE_LA_MIDNIGHT).plusDays(1));
        assertThat(quota.reserve(waiting, texts(1)).items()).isEqualTo(1); // 서버 예산은 새 날
        assertThat(quota.reserve(first, texts(1)).items()).isZero();       // 기기 몫은 한국 날짜 그대로 이어짐
        assertThat(usage.llmCalls(la(BEFORE_LA_MIDNIGHT)).older()).isEqualTo(7);
        assertThat(usage.llmCalls(la(AFTER_LA_MIDNIGHT)).older()).isEqualTo(1);
    }

    @Test
    void 서머타임에는_태평양_자정이_한국_16시다() {
        clock.now = LocalDateTime.of(2030, 7, 15, 15, 59);
        for (int i = 0; i < 4; i++) {
            quota.reserve(newDevice(), images(10)); // 예전 몫 7회 다 씀
        }
        assertThat(quota.reserve(newDevice(), texts(1)).items()).isZero();

        clock.now = LocalDateTime.of(2030, 7, 15, 16, 1); // PDT(UTC-7): 태평양 7/15 00:01

        assertThat(quota.reserve(newDevice(), texts(1)).items()).isEqualTo(1);
    }

    @Test
    void 자정을_넘겨_정산해도_예약한_날에서_돌려준다() {
        long device = newDevice();
        clock.now = LocalDateTime.of(2030, 11, 20, 23, 59);
        LocalDateTime reservedAt = clock.now;
        OlderQuota.Reservation r = quota.reserve(device, texts(4));

        clock.now = LocalDateTime.of(2030, 11, 21, 0, 1);
        quota.settle(device, r, 4, 0);

        assertThat(usage.deviceOlderCount(device, kst(reservedAt))).isZero();
        assertThat(usage.deviceOlderCount(device, kst(clock.now))).isZero();
        assertThat(usage.llmCalls(la(reservedAt)).older()).isZero();
    }

    @Test
    void 동시에_예약해도_기기_한도를_넘지_않는다() throws Exception {
        long device = newDevice();
        int threads = 8;
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        try {
            List<Future<OlderQuota.Reservation>> futures = new ArrayList<>();
            for (int i = 0; i < threads; i++) {
                Callable<OlderQuota.Reservation> task = () -> {
                    start.await();
                    return quota.reserve(device, texts(3));
                };
                futures.add(pool.submit(task));
            }
            start.countDown();
            int granted = 0;
            for (Future<OlderQuota.Reservation> f : futures) {
                granted += f.get().items();
            }

            assertThat(granted).isEqualTo(10);
            assertThat(usage.deviceOlderCount(device, kst(clock.now))).isEqualTo(10);
        } finally {
            pool.shutdownNow();
        }
    }
}
