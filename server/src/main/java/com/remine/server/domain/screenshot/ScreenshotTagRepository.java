package com.remine.server.domain.screenshot;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

public interface ScreenshotTagRepository extends JpaRepository<ScreenshotTag, Long> {

    // 페이지 단위로 태그를 한 번에 가져와 목록의 N+1을 막는다.
    @Query("""
            select new com.remine.server.domain.screenshot.ScreenshotTagRow(st.screenshot.id, st.tag.name)
            from ScreenshotTag st
            where st.screenshot.id in :screenshotIds
            order by st.id
            """)
    List<ScreenshotTagRow> findTagRows(@Param("screenshotIds") Collection<Long> screenshotIds);

    // 카테고리 × 태그 사용 횟수. 행 수는 (카테고리, 태그) 조합 수로 제한된다.
    @Query("""
            select new com.remine.server.domain.screenshot.CategoryTagCountRow(s.category, t.name, count(st))
            from ScreenshotTag st join st.screenshot s join st.tag t
            where s.device.id = :deviceId and s.category is not null
            group by s.category, t.name
            """)
    List<CategoryTagCountRow> countTagsByCategory(@Param("deviceId") Long deviceId);

    // 관심사 감지: 기간 안의 분석된 캡처 × 태그, 최신순. 행 수는 기간 안 캡처 수 × 캡처당 태그 수로 제한된다.
    @Query("""
            select new com.remine.server.domain.screenshot.InterestRow(
                t.id, t.name, s.id, s.localAssetId, s.category, s.takenAt)
            from ScreenshotTag st join st.screenshot s join st.tag t
            where s.device.id = :deviceId and s.takenAt >= :since and s.category is not null
            order by s.takenAt desc, s.id desc
            """)
    List<InterestRow> findInterestRows(@Param("deviceId") Long deviceId, @Param("since") LocalDateTime since);
}
