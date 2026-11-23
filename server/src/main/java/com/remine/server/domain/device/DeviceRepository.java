package com.remine.server.domain.device;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface DeviceRepository extends JpaRepository<Device, Long> {

    @Query("select d from Device d where d.tokenHash = :tokenHash")
    Optional<Device> findByTokenHash(byte[] tokenHash);

    @Query("select d.id from Device d order by d.id")
    List<Long> findAllIds();

    /** 기기 등록 시각. 이보다 먼저 찍힌 캡처가 예전 스크린샷이다. 없는 기기면 빈 값. */
    @Query("select d.createdAt from Device d where d.id = :id")
    Optional<LocalDateTime> findCreatedAtById(Long id);
}
