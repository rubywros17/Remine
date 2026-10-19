package com.remine.server.classifier;

import com.remine.server.domain.screenshot.Category;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 키워드 포함 여부로 분류하는 임시 구현. remine.classifier=fake(기본)일 때 쓰고 이미지는 무시한다. */
public class FakeClassifier implements Classifier {

    private static final int MAX_TAGS = 3;
    private static final int SUMMARY_LENGTH = 30;

    // 위에서부터 먼저 매칭되는 카테고리가 이긴다.
    private static final Map<Category, List<String>> KEYWORDS = new LinkedHashMap<>();

    static {
        KEYWORDS.put(Category.SHOPPING, List.of("구매", "장바구니", "배송", "할인", "원"));
        KEYWORDS.put(Category.ENTERTAINMENT, List.of("영화", "드라마", "넷플릭스", "시즌", "에피소드", "뮤지컬", "공연", "전시"));
        KEYWORDS.put(Category.PLACE, List.of("맛집", "카페", "영업시간", "주소", "메뉴"));
        KEYWORDS.put(Category.SCHEDULE, List.of("예약", "일정", "체크인"));
        KEYWORDS.put(Category.CHAT, List.of("ㅋㅋ", "ㅎㅎ"));
        KEYWORDS.put(Category.INFO, List.of("방법", "꿀팁", "팁"));
    }

    @Override
    public ClassificationResult classify(String ocrText, byte[] jpegImage) {
        String summary = ocrText.length() <= SUMMARY_LENGTH
                ? ocrText
                : ocrText.substring(0, SUMMARY_LENGTH) + "…";

        for (Map.Entry<Category, List<String>> entry : KEYWORDS.entrySet()) {
            List<String> matched = entry.getValue().stream()
                    .filter(ocrText::contains)
                    .limit(MAX_TAGS)
                    .toList();
            if (!matched.isEmpty()) {
                return new ClassificationResult(entry.getKey(), matched, summary);
            }
        }
        return new ClassificationResult(Category.ETC, List.of(), summary);
    }
}
