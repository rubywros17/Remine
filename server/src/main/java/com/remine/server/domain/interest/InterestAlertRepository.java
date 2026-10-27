package com.remine.server.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

public interface InterestAlertRepository extends JpaRepository<InterestAlert, Long> {

    boolean existsByDeviceIdAndWeekStart(Long deviceId, LocalDate weekStart);

    // 쿨다운: 이 주 이후(after 초과)에 알림 후보가 된 태그.
    @Query("select a.tag.id from InterestAlert a where a.device.id = :deviceId and a.weekStart > :after")
    List<Long> findTagIdsSince(@Param("deviceId") Long deviceId, @Param("after") LocalDate after);

    // 이번 주에 보낼 것: 토큰이 있는 기기의 PENDING. 문구에 태그 이름이 들어가 tag까지 한 번에 읽는다.
    @Query("""
            select a from InterestAlert a join fetch a.device d join fetch a.tag
            where a.status = com.remine.server.domain.interest.InterestAlert.Status.PENDING
              and a.weekStart = :weekStart and d.fcmToken is not null
            order by a.id""")
    List<InterestAlert> findPendingToSend(@Param("weekStart") LocalDate weekStart);

    // 그 주에 못 보낸 후보는 지나간 관심사라 보내지 않는다. 영원히 PENDING으로 남지 않게 정리한다.
    @Modifying
    @Query("""
            update InterestAlert a set a.status = com.remine.server.domain.interest.InterestAlert.Status.EXPIRED
            where a.status = com.remine.server.domain.interest.InterestAlert.Status.PENDING
              and a.weekStart < :weekStart""")
    int expireBefore(@Param("weekStart") LocalDate weekStart);
}
