package com.remine.server;

import com.remine.server.domain.device.Device;
import com.remine.server.domain.device.DeviceRepository;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.cfg.JdbcSettings;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.TimeZone;

import static org.assertj.core.api.Assertions.assertThat;

/** 배포 서버의 OS 시간대(UTC 등)와 무관하게 JVM 기본값·Clock 빈·Hibernate JDBC 시간대가 모두 ServerApplication.ZONE이다. */
@SpringBootTest
class TimeZoneTest {

    @Autowired Clock clock;
    @Autowired EntityManagerFactory entityManagerFactory;
    @Autowired DeviceRepository deviceRepository;
    @Autowired JdbcTemplate jdbcTemplate;

    @Test
    void JVM_기본값_Clock_Hibernate가_같은_시간대다() {
        ZoneId zone = ZoneId.of(ServerApplication.ZONE);

        assertThat(TimeZone.getDefault().toZoneId()).isEqualTo(zone);
        assertThat(clock.getZone()).isEqualTo(zone);
        assertThat(entityManagerFactory.getProperties().get(JdbcSettings.JDBC_TIME_ZONE)).isEqualTo(ServerApplication.ZONE);
    }

    @Test
    void Clock을_거치지_않는_저장_시각도_DB에_Clock과_같은_기준으로_남는다() {
        // created_at은 @CreationTimestamp(JVM 기본 시간대)로 채워진다. DB에서 그대로 읽어 Clock의 "지금"과 비교한다.
        Long id = deviceRepository.save(new Device("token")).getId();

        LocalDateTime stored = jdbcTemplate.queryForObject(
                "select created_at from device where id = ?", LocalDateTime.class, id);

        assertThat(Duration.between(stored, LocalDateTime.now(clock)).abs()).isLessThan(Duration.ofMinutes(1));
    }
}
