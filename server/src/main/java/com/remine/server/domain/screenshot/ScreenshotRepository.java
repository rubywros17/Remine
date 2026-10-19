package com.remine.server.domain.screenshot;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Set;

public interface ScreenshotRepository extends JpaRepository<Screenshot, Long> {

    /** 이미 분석이 끝난 캡처만. 분석에 실패해 analyzed_at이 null인 행은 다시 분석 대상이라 여기에 포함하지 않는다. */
    @Query("select s.localAssetId from Screenshot s "
            + "where s.device.id = :deviceId and s.localAssetId in :localAssetIds and s.analyzedAt is not null")
    Set<String> findAnalyzedLocalAssetIds(@Param("deviceId") Long deviceId,
                                          @Param("localAssetIds") Collection<String> localAssetIds);

    /** 저장 단계에서 이미 있는 행(= 앞선 요청에서 분석에 실패해 남은 행)을 찾아 갱신하기 위한 조회. */
    @Query("select s from Screenshot s where s.device.id = :deviceId and s.localAssetId in :localAssetIds")
    List<Screenshot> findByDeviceAndLocalAssetIds(@Param("deviceId") Long deviceId,
                                                  @Param("localAssetIds") Collection<String> localAssetIds);

    /**
     * 분석이 끝난 캡처만 돌려준다(분석에 실패해 카테고리가 null인 행은 목록에 섞이지 않는다).
     * category, tag는 null이면 조건에서 빠진다.
     * 태그 필터는 join 대신 exists로 걸어 한 스크린샷이 중복 행으로 나오지 않게 한다(페이지네이션 정확성).
     */
    @Query("""
            select s from Screenshot s
            where s.device.id = :deviceId
              and s.analyzedAt is not null
              and (:category is null or s.category = :category)
              and (:tag is null or exists (
                    select 1 from ScreenshotTag st where st.screenshot = s and st.tag.name = :tag))
            order by s.takenAt desc, s.id desc
            """)
    Page<Screenshot> search(@Param("deviceId") Long deviceId,
                            @Param("category") Category category,
                            @Param("tag") String tag,
                            Pageable pageable);

    @Query("""
            select new com.remine.server.domain.screenshot.CategoryCountRow(s.category, count(s))
            from Screenshot s
            where s.device.id = :deviceId and s.category is not null
            group by s.category
            """)
    List<CategoryCountRow> countByCategory(@Param("deviceId") Long deviceId);

    /**
     * 카테고리별 최신 limit개의 localAssetId. 행: [category(String), localAssetId(String)]
     * window 함수(row_number)로 카테고리 수와 무관하게 쿼리 1번. (H2 / PostgreSQL / MySQL 8 공통 문법)
     */
    @Query(value = """
            select t.category, t.local_asset_id
            from (select category, local_asset_id,
                         row_number() over (partition by category order by taken_at desc, id desc) as rn
                  from screenshot
                  where device_id = :deviceId and category is not null) t
            where t.rn <= :limit
            order by t.category, t.rn
            """, nativeQuery = true)
    List<Object[]> findRecentAssetIdsByCategory(@Param("deviceId") Long deviceId, @Param("limit") int limit);
}
