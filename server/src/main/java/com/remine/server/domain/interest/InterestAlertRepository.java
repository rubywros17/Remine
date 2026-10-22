package com.remine.server.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

public interface InterestAlertRepository extends JpaRepository<InterestAlert, Long> {

    boolean existsByDeviceIdAndWeekStart(Long deviceId, LocalDate weekStart);

    // 쿨다운: 이 주 이후(after 초과)에 알림 후보가 된 태그.
    @Query("select a.tag.id from InterestAlert a where a.device.id = :deviceId and a.weekStart > :after")
    List<Long> findTagIdsSince(@Param("deviceId") Long deviceId, @Param("after") LocalDate after);
}
