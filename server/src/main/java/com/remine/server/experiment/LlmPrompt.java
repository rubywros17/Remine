package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.screenshot.Category;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.ArrayList;
import java.util.List;

/** 모든 후보가 같은 프롬프트를 쓰도록 한 곳에 둔다. 카테고리는 {@link Category} 7개로 고정. */
public final class LlmPrompt {

    private static final int MAX_OCR_CHARS = 3000;

    public static final String SYSTEM = """
            너는 스마트폰 스크린샷의 OCR 텍스트를 분류하는 분류기다.
            category는 아래 7개 중 정확히 하나만 고른다.
            - SHOPPING: 상품, 가격, 구매, 장바구니, 배송
            - MOVIE_DRAMA: 영화·드라마·OTT 작품 정보
            - PLACE: 맛집, 카페, 여행지, 주소, 영업시간
            - INFO: 정보·꿀팁·뉴스·방법 설명
            - CHAT: 메신저·댓글 대화
            - SCHEDULE: 일정, 예약, 티켓, 알림
            - ETC: 위에 해당하지 않거나 의미 있는 글자가 없음
            응답은 JSON 객체 하나만 출력한다. 설명, 마크다운, 코드블록은 쓰지 않는다.
            {"category": "<위 7개 중 하나>", "tags": ["짧은 명사 최대 3개"], "summary": "한 문장 요약(40자 이내)"}
            """;

    private LlmPrompt() {
    }

    public static String user(String ocrText) {
        String text = ocrText.length() > MAX_OCR_CHARS ? ocrText.substring(0, MAX_OCR_CHARS) : ocrText;
        return "OCR 텍스트:\n" + text;
    }

    /** ok=false면 JSON이 아니거나 카테고리가 7개 밖이다. 이 경우 결과는 ETC로 둔다. */
    public record Parsed(ClassificationResult result, boolean ok) {
    }

    public static Parsed parse(JsonMapper mapper, String raw) {
        try {
            JsonNode node = mapper.readTree(extractJsonObject(raw));
            Category category = Category.valueOf(node.path("category").asString("").trim().toUpperCase());
            List<String> tags = new ArrayList<>();
            node.path("tags").forEach(tag -> tags.add(tag.asString("").trim()));
            tags.removeIf(String::isEmpty);
            return new Parsed(new ClassificationResult(category, tags, node.path("summary").asString("")), true);
        } catch (RuntimeException e) {
            return new Parsed(new ClassificationResult(Category.ETC, List.of(), ""), false);
        }
    }

    // 모델이 코드펜스나 앞뒤 설명을 붙여도 첫 '{' ~ 마지막 '}'만 JSON으로 본다.
    static String extractJsonObject(String raw) {
        int start = raw.indexOf('{');
        int end = raw.lastIndexOf('}');
        if (start < 0 || end < start) {
            throw new IllegalArgumentException("JSON 객체가 없음");
        }
        return raw.substring(start, end + 1);
    }
}
