package com.remine.server.domain.screenshot;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

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
}
