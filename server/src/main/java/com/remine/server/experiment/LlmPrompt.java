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

    /**
     * v2 경계 규칙. 카테고리 정의(DEFINITIONS)는 v1과 같게 두고, 경계가 애매할 때만 적용되는 일반 원칙을 따로 둔다.
     * 정의를 바꾸지 않으므로 같은 labels.csv로 v1과 공정하게 비교된다. 특정 캡처·앱을 겨냥한 문구는 넣지 않는다.
     * experiment/README.md의 "프롬프트 v2 경계 규칙" 절과 같은 문구여야 한다(LlmPromptTest가 검사).
     */
    public static final List<String> RULES_V2 = List.of(
            "SHOPPING은 구매 의도가 보일 때만 고른다. 가격·구매 버튼·장바구니·주문처럼 사는 행동으로 이어지는 단서가 있어야 하며, "
                    + "가격이나 상품이 보여도 정보를 전달하는 내용(소개·비교·팁·후기 정리)이 중심이면 INFO를 고른다.",
            "게시·작성·업로드 날짜(예: \"2시간 전\", 게시일)는 일정이 아니다. "
                    + "SCHEDULE은 앞으로 갈 날짜·시간과 함께 해야 할 일, 장소, 예약이 같이 있을 때만 고른다.");

    /** v1 시스템 프롬프트 (규칙 없음). 처음 실험에서 쓴 문구이며 바뀌면 안 된다. */
    public static final String SYSTEM = buildSystem(List.of());

    private static final String SYSTEM_V2 = buildSystem(RULES_V2);

    private static String buildSystem(List<String> rules) {
        String definitions = DEFINITIONS.entrySet().stream()
                .map(e -> "- " + e.getKey() + ": " + e.getValue())
                .collect(Collectors.joining("\n"));
        String ruleBlock = rules.isEmpty() ? "" : "경계가 애매할 때는 위 정의보다 아래 규칙을 우선한다.\n"
                + rules.stream().map(rule -> "- " + rule).collect(Collectors.joining("\n")) + "\n";
        return """
                너는 스마트폰 스크린샷의 OCR 텍스트를 분류하는 분류기다.
                category는 아래 7개 중 정확히 하나만 고른다.
                %s
                %s응답은 JSON 객체 하나만 출력한다. 설명, 마크다운, 코드블록은 쓰지 않는다.
                {"category": "<위 7개 중 하나>", "tags": ["짧은 명사 최대 3개"], "summary": "한 문장 요약(40자 이내)"}
                """.formatted(definitions, ruleBlock);
    }

    /** 버전별 시스템 프롬프트. v1은 비교 기준이라 바뀌면 안 된다(PromptVersionTest의 스냅샷). */
    public static String system(PromptVersion version) {
        return switch (version) {
            case V1 -> SYSTEM;
            case V2 -> SYSTEM_V2;
        };
    }

    private static Map<Category, String> definitions() {
        Map<Category, String> map = new EnumMap<>(Category.class);
        map.put(Category.SHOPPING, "상품, 가격, 구매, 장바구니, 배송. 가격·할인·장바구니·배송이 보이면 대개 SHOPPING");
        map.put(Category.ENTERTAINMENT, "영화·드라마·OTT·연극·뮤지컬·공연·전시·책·음악 등 보고 싶은 작품·콘텐츠");
        map.put(Category.PLACE, "맛집·카페·팝업스토어·여행지 등 \"가보고 싶은 곳\" (운영 기간이 있어도 장소가 핵심이면 PLACE). 주소·영업시간·메뉴·위치가 보이면 대개 PLACE");
        map.put(Category.INFO, "뉴스·꿀팁·방법 설명, 레시피·DIY·코디처럼 \"알아두거나 따라 해보려는 것\"");
        map.put(Category.CHAT, "메신저·댓글 대화");
        map.put(Category.SCHEDULE, "일정, 예약, 티켓, 알림. 작품 자체가 아니라 날짜·예약·티켓 오픈이 핵심이면 SCHEDULE. 특정 날짜·시간, 예매 오픈, 예약 완료가 핵심이면 SCHEDULE");
        map.put(Category.ETC, "위에 해당하지 않거나 의미 있는 글자가 없음");
        return Collections.unmodifiableMap(map);
    }

    private LlmPrompt() {
    }

    public static String user(String ocrText) {
        String text = ocrText.length() > MAX_OCR_CHARS ? ocrText.substring(0, MAX_OCR_CHARS) : ocrText;
        return "OCR 텍스트:\n" + text;
    }

    /** text+image 후보용. 시스템 프롬프트는 그대로이고 이미지가 함께 있다는 한 줄만 더한다. */
    public static String userWithImage(String ocrText) {
        return user(ocrText) + "\n\n위 텍스트는 첨부한 스크린샷 이미지의 OCR 결과다. 이미지도 함께 참고해 분류하라.";
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
