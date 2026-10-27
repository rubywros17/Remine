package com.remine.server;

import org.hibernate.cfg.JdbcSettings;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.hibernate.autoconfigure.HibernatePropertiesCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.time.Clock;
import java.time.ZoneId;
import java.util.TimeZone;

@SpringBootApplication
@EnableScheduling
public class ServerApplication {

	/**
	 * 서버의 시간대. taken_at이 기기(한국) 시각이라 "지금"·주간 집계·DB 시각을 모두 이 기준에 맞춘다.
	 * 배포 서버가 UTC여도 동작이 같도록 JVM 기본값·Clock·스케줄·Hibernate JDBC 시간대를 이 상수 하나에서 정한다.
	 */
	public static final String ZONE = "Asia/Seoul";

	// main과 @SpringBootTest 모두 이 클래스를 로드하므로 테스트에도 적용된다.
	// (Clock을 거치지 않는 LocalDateTime.now()·@CreationTimestamp도 같은 기준이 된다)
	static {
		TimeZone.setDefault(TimeZone.getTimeZone(ZONE));
	}

	public static void main(String[] args) {
		SpringApplication.run(ServerApplication.class, args);
	}

	/** "지금"은 이 빈에서만 읽는다(관심사 기간·주간 집계). 테스트는 Clock.fixed로 바꾼다. */
	@Bean
	Clock clock() {
		return Clock.system(ZoneId.of(ZONE));
	}

	/** LocalDateTime ↔ timestamp 변환 기준. JVM 기본값과 같지만 명시해 둔다. */
	@Bean
	HibernatePropertiesCustomizer jdbcTimeZone() {
		return properties -> properties.put(JdbcSettings.JDBC_TIME_ZONE, ZONE);
	}
}
