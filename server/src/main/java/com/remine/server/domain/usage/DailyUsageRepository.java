package com.remine.server.domain.usage;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;

/**
 * 하루 사용량 카운터(device_daily_usage, llm_daily_usage). 엔티티 없이 SQL로 다룬다:
 * 날짜별 행을 없으면 만들고(upsert) 행 잠금 뒤 더하는 원자적 갱신이 JPA보다 SQL로 더 분명하다.
 * {@code lock*}은 행을 잠그므로 호출하는 쪽 트랜잭션 안에서 쓴다. 더하는 값은 0 아래로 내려가지 않는다(환불이 과해도 안전).
 */
@Repository
@RequiredArgsConstructor
public class DailyUsageRepository {

    private final JdbcClient jdbc;

    /** 서버 전체 하루 호출 수. */
    public record LlmCalls(int older, int newer) {

        public int total() {
            return older + newer;
        }
    }

    /** 기기의 그날 예전 스크린샷 수를 행 잠금과 함께 읽는다(행이 없으면 0으로 만든다). */
    public int lockDeviceOlderCount(long deviceId, LocalDate date) {
        jdbc.sql("""
                        insert into device_daily_usage (device_id, usage_date, older_count) values (:d, :date, 0)
                        on conflict (device_id, usage_date) do nothing""")
                .param("d", deviceId).param("date", date).update();
        return jdbc.sql("select older_count from device_daily_usage where device_id = :d and usage_date = :date for update")
                .param("d", deviceId).param("date", date).query(Integer.class).single();
    }

    public int deviceOlderCount(long deviceId, LocalDate date) {
        return jdbc.sql("select older_count from device_daily_usage where device_id = :d and usage_date = :date")
                .param("d", deviceId).param("date", date).query(Integer.class).optional().orElse(0);
    }

    public void addDeviceOlderCount(long deviceId, LocalDate date, int delta) {
        jdbc.sql("""
                        insert into device_daily_usage (device_id, usage_date, older_count) values (:d, :date, greatest(0, :delta))
                        on conflict (device_id, usage_date)
                        do update set older_count = greatest(0, device_daily_usage.older_count + :delta)""")
                .param("d", deviceId).param("date", date).param("delta", delta).update();
    }

    /** 그날 서버 전체 호출 수를 행 잠금과 함께 읽는다(행이 없으면 0으로 만든다). */
    public LlmCalls lockLlmCalls(LocalDate date) {
        jdbc.sql("insert into llm_daily_usage (usage_date) values (:date) on conflict (usage_date) do nothing")
                .param("date", date).update();
        return jdbc.sql("select older_calls, new_calls from llm_daily_usage where usage_date = :date for update")
                .param("date", date)
                .query((rs, n) -> new LlmCalls(rs.getInt("older_calls"), rs.getInt("new_calls"))).single();
    }

    public LlmCalls llmCalls(LocalDate date) {
        return jdbc.sql("select older_calls, new_calls from llm_daily_usage where usage_date = :date")
                .param("date", date)
                .query((rs, n) -> new LlmCalls(rs.getInt("older_calls"), rs.getInt("new_calls")))
                .optional().orElse(new LlmCalls(0, 0));
    }

    public void addLlmCalls(LocalDate date, int olderDelta, int newDelta) {
        jdbc.sql("""
                        insert into llm_daily_usage (usage_date, older_calls, new_calls)
                        values (:date, greatest(0, :o), greatest(0, :n))
                        on conflict (usage_date) do update set
                            older_calls = greatest(0, llm_daily_usage.older_calls + :o),
                            new_calls = greatest(0, llm_daily_usage.new_calls + :n)""")
                .param("date", date).param("o", olderDelta).param("n", newDelta).update();
    }
}
