package com.remine.server.domain.screenshot;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.Set;

public interface ScreenshotRepository extends JpaRepository<Screenshot, Long> {

    @Query("select s.localAssetId from Screenshot s "
            + "where s.device.id = :deviceId and s.localAssetId in :localAssetIds")
    Set<String> findExistingLocalAssetIds(@Param("deviceId") Long deviceId,
                                          @Param("localAssetIds") Collection<String> localAssetIds);
}
