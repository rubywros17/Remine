package com.remine.server.domain.device;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface DeviceRepository extends JpaRepository<Device, Long> {

    @Query("select d.id from Device d order by d.id")
    List<Long> findAllIds();
}
