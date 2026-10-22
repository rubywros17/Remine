package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.tag.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class TagCleanerTest {

    @Test
    void 키는_샵_공백_대소문자를_무시한다() {
        assertThat(Tag.keyOf("#니트 가디건")).isEqualTo(Tag.keyOf("니트가디건"));
        assertThat(Tag.keyOf("Air  Max")).isEqualTo(Tag.keyOf("airmax"));
        assertThat(new Tag("Air Max").getName()).isEqualTo("Air Max"); // 표시 이름은 그대로
    }

    @Test
    void 같은_키는_처음_표기만_남기고_빈_값을_뺀다() {
        TagCleaner cleaner = cleaner();

        assertThat(cleaner.clean(Arrays.asList("#니트  가디건", "니트가디건", "", " ", "#", null, "Nike", "NIKE")))
                .containsExactly("니트 가디건", "Nike");
    }

    @Test
    void 설정_파일의_불용어_화면_문구와_카테고리명을_뺀다() throws IOException {
        TagCleaner cleaner = new TagCleaner(propertiesFromApplicationYaml());

        assertThat(cleaner.clean(List.of("장바구니", "무료 배송", "#구매하기", "쇼핑", "맛집/장소", "정보", "니트 가디건")))
                .containsExactly("니트 가디건");
    }

    private static TagCleaner cleaner() {
        return new TagCleaner(new RemineProperties(null, null, null, null,
                new RemineProperties.Tags(List.of()), null));
    }

    // 운영 설정(application.yaml)의 목록 그대로 검사한다(목록이 한 곳에만 있는지도 함께 확인).
    private static RemineProperties propertiesFromApplicationYaml() throws IOException {
        StandardEnvironment env = new StandardEnvironment();
        new YamlPropertySourceLoader().load("app", new ClassPathResource("application.yaml"))
                .forEach(env.getPropertySources()::addLast);
        RemineProperties.Tags tags = new Binder(ConfigurationPropertySources.get(env))
                .bind("remine.tags", RemineProperties.Tags.class).get();
        return new RemineProperties(null, null, null, null, tags, null);
    }
}
