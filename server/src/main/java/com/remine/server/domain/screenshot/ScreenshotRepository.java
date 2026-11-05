package com.remine.server.domain.screenshot;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.Set;

public interface ScreenshotRepository extends JpaRepository<Screenshot, Long> {

    /** 이미 분석이 끝난 캡처만. 분석에 실패해 analyzed_at이 null인 행은 다시 분석 대상이라 여기에 포함하지 않는다. */
    @Query("select s.localAssetId from Screenshot s "
            + "where s.device.id = :deviceId and s.localAssetId in :localAssetIds and s.analyzedAt is not null")
    Set<String> findAnalyzedLocalAssetIds(@Param("deviceId") Long deviceId,
                                          @Param("localAssetIds") Collection<String> localAssetIds);

    /** 소유까지 한 쿼리로 확인한다. 없는 id와 다른 기기의 캡처는 둘 다 빈 결과다. */
    @Query("select s from Screenshot s where s.id = :id and s.device.id = :deviceId")
    Optional<Screenshot> findByIdAndDeviceId(@Param("id") Long id, @Param("deviceId") Long deviceId);

    /** 저장 단계에서 이미 있는 행(= 앞선 요청에서 분석에 실패해 남은 행)을 찾아 갱신하기 위한 조회. */
    @Query("select s from Screenshot s where s.device.id = :deviceId and s.localAssetId in :localAssetIds")
    List<Screenshot> findByDeviceAndLocalAssetIds(@Param("deviceId") Long deviceId,
                                                  @Param("localAssetIds") Collection<String> localAssetIds);

    /**
     * 분석이 끝난 캡처만 돌려준다(분석에 실패해 카테고리가 null인 행은 목록에 섞이지 않는다).
     * category, tagKey는 null이면 조건에서 빠진다. tagKey는 {@code Tag.keyOf}로 정규화한 값이라
     * "니트 가디건"으로 찾아도 "니트가디건" 캡처가 나온다(관심사 집계와 같은 기준).
     * 태그 필터는 join 대신 exists로 걸어 한 스크린샷이 중복 행으로 나오지 않게 한다(페이지네이션 정확성).
     */
    @Query("""
            select s from Screenshot s
            where s.device.id = :deviceId
              and s.analyzedAt is not null
              and (:category is null or s.category = :category)
              and (:tagKey is null or exists (
                    select 1 from ScreenshotTag st where st.screenshot = s and st.tag.normalizedName = :tagKey))
            order by s.takenAt desc, s.id desc
            """)
    Page<Screenshot> search(@Param("deviceId") Long deviceId,
                            @Param("category") Category category,
                            @Param("tagKey") String tagKey,
                            Pageable pageable);

    @Query("""
            select new com.remine.server.domain.screenshot.CategoryCountRow(s.category, count(s))
            from Screenshot s
            where s.device.id = :deviceId and s.category is not null
            group by s.category
            """)
    List<CategoryCountRow> countByCategory(@Param("deviceId") Long deviceId);

    /** 정확도 집계(F-05): 분석된 캡처를 (auto_category, category, category_source)로 묶어 쿼리 1번. */
    @Query("""
            select new com.remine.server.domain.screenshot.AccuracyRow(
                       s.autoCategory, s.category, s.categorySource, count(s))
            from Screenshot s
            where s.device.id = :deviceId and s.analyzedAt is not null
            group by s.autoCategory, s.category, s.categorySource
            """)
    List<AccuracyRow> countForAccuracy(@Param("deviceId") Long deviceId);

    /**
     * 카테고리별 최신 limit개의 localAssetId. 행: [category(String), localAssetId(String)]
     * window 함수(row_number)로 카테고리 수와 무관하게 쿼리 1번. (PostgreSQL / MySQL 8 공통 문법)
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

    /** 이미 휴지통에 있는 캡처의 시각은 바꾸지 않는다(재전송해도 결과가 같게). */
    @Modifying(clearAutomatically = true)
    @Query("""
            update Screenshot s set s.trashedAt = :at
            where s.device.id = :deviceId and s.localAssetId in :localAssetIds and s.trashedAt is null
            """)
    int markTrashed(@Param("deviceId") Long deviceId,
                    @Param("localAssetIds") Collection<String> localAssetIds,
                    @Param("at") LocalDateTime at);

    @Modifying(clearAutomatically = true)
    @Query("""
            update Screenshot s set s.trashedAt = null
            where s.device.id = :deviceId and s.localAssetId in :localAssetIds and s.trashedAt is not null
            """)
    int clearTrashed(@Param("deviceId") Long deviceId,
                     @Param("localAssetIds") Collection<String> localAssetIds);

    @Modifying(clearAutomatically = true)
    @Query("delete from Screenshot s where s.device.id = :deviceId and s.localAssetId in :localAssetIds")
    int deleteByDeviceAndAssetIds(@Param("deviceId") Long deviceId,
                                  @Param("localAssetIds") Collection<String> localAssetIds);
}
