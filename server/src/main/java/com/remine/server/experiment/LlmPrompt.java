package com.remine.server.experiment;

import com.remine.server.classifier.ClassificationResult;
import com.remine.server.domain.screenshot.Category;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** 모든 후보가 같은 프롬프트를 쓰도록 한 곳에 둔다. 카테고리는 {@link Category} 7개로 고정. */
public final class LlmPrompt {

    private static final int MAX_OCR_CHARS = 3000;

    /**
     * 카테고리 정의. 프롬프트와 experiment/README.md의 라벨링 기준 표가 모두 이 문구를 쓴다.
     * 문구를 바꾸면 README 표도 같이 고쳐야 하며, 어긋나면 LlmPromptTest가 실패한다.
     */
    public static final Map<Category, String> DEFINITIONS = definitions();

    public static final String SYSTEM = """
            너는 스마트폰 스크린샷의 OCR 텍스트를 분류하는 분류기다.
            category는 아래 7개 중 정확히 하나만 고른다.
            %s
            응답은 JSON 객체 하나만 출력한다. 설명, 마크다운, 코드블록은 쓰지 않는다.
            {"category": "<위 7개 중 하나>", "tags": ["짧은 명사 최대 3개"], "summary": "한 문장 요약(40자 이내)"}
            """.formatted(DEFINITIONS.entrySet().stream()
            .map(e -> "- " + e.getKey() + ": " + e.getValue())
            .collect(Collectors.joining("\n")));

    private static Map<Category, String> definitions() {
        Map<Category, String> map = new EnumMap<>(Category.class);
        map.put(Category.SHOPPING, "상품, 가격, 구매, 장바구니, 배송");
        map.put(Category.ENTERTAINMENT, "영화·드라마·OTT·연극·뮤지컬·공연·전시·책·음악 등 보고 싶은 작품·콘텐츠");
        map.put(Category.PLACE, "맛집·카페·팝업스토어·여행지 등 \"가보고 싶은 곳\" (운영 기간이 있어도 장소가 핵심이면 PLACE)");
        map.put(Category.INFO, "뉴스·꿀팁·방법 설명, 레시피·DIY·코디처럼 \"알아두거나 따라 해보려는 것\"");
        map.put(Category.CHAT, "메신저·댓글 대화");
        map.put(Category.SCHEDULE, "일정, 예약, 티켓, 알림. 작품 자체가 아니라 날짜·예약·티켓 오픈이 핵심이면 SCHEDULE");
        map.put(Category.ETC, "위에 해당하지 않거나 의미 있는 글자가 없음");
        return Collections.unmodifiableMap(map);
    }

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
