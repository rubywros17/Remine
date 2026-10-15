package com.remine.server.classifier;

import com.remine.server.domain.screenshot.Category;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class FakeClassifierTest {

    private final FakeClassifier classifier = new FakeClassifier();

    @Test
    void 가격_키워드가_있으면_쇼핑으로_분류하고_매칭된_키워드를_태그로_준다() {
        ClassificationResult result = classifier.classify("니트 가디건 39,000원 구매하기");

        assertThat(result.category()).isEqualTo(Category.SHOPPING);
        assertThat(result.tags()).containsExactly("구매", "원");
    }

    @Test
    void 공연_전시_키워드는_문화생활로_분류한다() {
        assertThat(classifier.classify("뮤지컬 캐스팅 안내").category()).isEqualTo(Category.ENTERTAINMENT);
        assertThat(classifier.classify("전시 관람 후기").category()).isEqualTo(Category.ENTERTAINMENT);
    }

    @Test
    void 매칭되는_키워드가_없으면_기타() {
        ClassificationResult result = classifier.classify("lorem ipsum");

        assertThat(result.category()).isEqualTo(Category.ETC);
        assertThat(result.tags()).isEmpty();
    }

    @Test
    void 긴_텍스트는_요약이_잘린다() {
        ClassificationResult result = classifier.classify("a".repeat(100));

        assertThat(result.summary()).hasSize(31).endsWith("…");
    }
}
