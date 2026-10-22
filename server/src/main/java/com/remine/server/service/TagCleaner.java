package com.remine.server.service;

import com.remine.server.classifier.RemineProperties;
import com.remine.server.domain.tag.Tag;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 모델이 낸 태그를 저장 전에 정리한다. 관심사 빈도 집계가 화면 문구·카테고리명으로 오염되지 않게 하기 위함이다.
 * 불용어 목록은 설정(remine.tags.stopwords) 한 곳에만 있고, 비교는 {@link Tag#keyOf} 키로 한다.
 */
@Component
public class TagCleaner {

    private final Set<String> stopwordKeys;

    public TagCleaner(RemineProperties properties) {
        this.stopwordKeys = properties.tags().stopwords().stream().map(Tag::keyOf).collect(Collectors.toSet());
    }

    /** 빈 값·불용어를 빼고, 키가 같은 태그는 처음 나온 표기 하나만 남긴다('#'은 떼고 공백은 정리한다). */
    public List<String> clean(List<String> tags) {
        Map<String, String> byKey = new LinkedHashMap<>();
        for (String tag : tags) {
            if (tag == null) {
                continue;
            }
            String display = tag.replace("#", "").strip().replaceAll("\\s+", " ");
            String key = Tag.keyOf(display);
            if (!key.isEmpty() && !stopwordKeys.contains(key)) {
                byKey.putIfAbsent(key, display);
            }
        }
        return List.copyOf(byKey.values());
    }
}
