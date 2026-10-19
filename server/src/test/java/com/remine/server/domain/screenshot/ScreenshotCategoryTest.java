package com.remine.server.domain.screenshot;

import com.remine.server.domain.device.Device;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.time.LocalDateTime;
import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ScreenshotCategoryTest {

    private Screenshot screenshot() {
        return new Screenshot(new Device("t"), "a1", LocalDateTime.now(), "앱", "글");
    }

    @Test
    void 첫_분석은_autoCategory와_category를_채우고_출처는_AUTO다() {
        Screenshot s = screenshot();

        s.applyAnalysis(Category.SHOPPING, "요약");

        assertThat(s.getAutoCategory()).isEqualTo(Category.SHOPPING);
        assertThat(s.getCategory()).isEqualTo(Category.SHOPPING);
        assertThat(s.getCategorySource()).isEqualTo(CategorySource.AUTO);
        assertThat(s.getAnalyzedAt()).isNotNull();
    }

    @Test
    void 사용자_수정은_category와_출처만_바꾸고_autoCategory는_그대로다() {
        Screenshot s = screenshot();
        s.applyAnalysis(Category.SHOPPING, "요약");

        s.changeCategoryByUser(Category.PLACE);

        assertThat(s.getCategory()).isEqualTo(Category.PLACE);
        assertThat(s.getCategorySource()).isEqualTo(CategorySource.USER);
        assertThat(s.getAutoCategory()).isEqualTo(Category.SHOPPING);
    }

    @Test
    void 같은_값으로_수정해도_USER가_된다() {
        Screenshot s = screenshot();
        s.applyAnalysis(Category.INFO, "요약");

        s.changeCategoryByUser(Category.INFO);

        assertThat(s.getCategorySource()).isEqualTo(CategorySource.USER);
        assertThat(s.getCategory()).isEqualTo(s.getAutoCategory());
    }

    @Test
    void 재분석은_USER_값을_덮어쓰지_않고_autoCategory도_바꾸지_않는다() {
        Screenshot s = screenshot();
        s.applyAnalysis(Category.SHOPPING, "첫 요약");
        s.changeCategoryByUser(Category.PLACE);

        s.applyAnalysis(Category.CHAT, "새 요약");

        assertThat(s.getCategory()).isEqualTo(Category.PLACE);
        assertThat(s.getCategorySource()).isEqualTo(CategorySource.USER);
        assertThat(s.getAutoCategory()).isEqualTo(Category.SHOPPING);
        assertThat(s.getSummary()).isEqualTo("새 요약"); // 요약은 카테고리와 독립
    }

    @Test
    void AUTO_행의_재분석은_category를_갱신하되_autoCategory는_최초_값을_유지한다() {
        Screenshot s = screenshot();
        s.applyAnalysis(Category.SHOPPING, "요약");

        s.applyAnalysis(Category.INFO, "요약");

        assertThat(s.getCategory()).isEqualTo(Category.INFO);
        assertThat(s.getAutoCategory()).isEqualTo(Category.SHOPPING);
    }

    @Test
    void 분석되지_않은_행은_수정할_수_없다() {
        assertThatThrownBy(() -> screenshot().changeCategoryByUser(Category.ETC))
                .isInstanceOf(IllegalStateException.class);
    }

    /** category·autoCategory·categorySource를 바꾸는 공개 경로는 applyAnalysis와 changeCategoryByUser뿐이다. */
    @Test
    void 카테고리_필드_세터가_없다() {
        assertThat(Arrays.stream(Screenshot.class.getMethods()).map(Method::getName))
                .doesNotContain("setCategory", "setAutoCategory", "setCategorySource");
    }
}
