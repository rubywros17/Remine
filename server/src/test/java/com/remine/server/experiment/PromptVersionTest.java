package com.remine.server.experiment;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PromptVersionTest {

    @Test
    void 생략하거나_비우면_v1() {
        assertThat(PromptVersion.parse(null)).isEqualTo(PromptVersion.V1);
        assertThat(PromptVersion.parse("")).isEqualTo(PromptVersion.V1);
        assertThat(PromptVersion.parse("  ")).isEqualTo(PromptVersion.V1);
    }

    @Test
    void 대소문자와_공백을_무시한다() {
        assertThat(PromptVersion.parse(" V1 ")).isEqualTo(PromptVersion.V1);
        assertThat(PromptVersion.parse(" V2 ")).isEqualTo(PromptVersion.V2);
    }

    @Test
    void 모르는_버전은_사용_가능한_목록과_함께_예외() {
        assertThatThrownBy(() -> PromptVersion.parse("v9"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("v9")
                .hasMessageContaining("v1");
    }

    @Test
    void v1_시스템_프롬프트는_처음_실험에서_쓴_문구와_같다() {
        // v1은 비교 기준이라 바뀌면 안 된다. 일부러 바꾼다면 새 버전을 만들고 이 스냅샷은 그대로 둔다.
        String expected = """
                너는 스마트폰 스크린샷의 OCR 텍스트를 분류하는 분류기다.
                category는 아래 7개 중 정확히 하나만 고른다.
                - SHOPPING: 상품, 가격, 구매, 장바구니, 배송. 가격·할인·장바구니·배송이 보이면 대개 SHOPPING
                - ENTERTAINMENT: 영화·드라마·OTT·연극·뮤지컬·공연·전시·책·음악 등 보고 싶은 작품·콘텐츠
                - PLACE: 맛집·카페·팝업스토어·여행지 등 "가보고 싶은 곳" (운영 기간이 있어도 장소가 핵심이면 PLACE). 주소·영업시간·메뉴·위치가 보이면 대개 PLACE
                - INFO: 뉴스·꿀팁·방법 설명, 레시피·DIY·코디처럼 "알아두거나 따라 해보려는 것"
                - CHAT: 메신저·댓글 대화
                - SCHEDULE: 일정, 예약, 티켓, 알림. 작품 자체가 아니라 날짜·예약·티켓 오픈이 핵심이면 SCHEDULE. 특정 날짜·시간, 예매 오픈, 예약 완료가 핵심이면 SCHEDULE
                - ETC: 위에 해당하지 않거나 의미 있는 글자가 없음
                응답은 JSON 객체 하나만 출력한다. 설명, 마크다운, 코드블록은 쓰지 않는다.
                {"category": "<위 7개 중 하나>", "tags": ["짧은 명사 최대 3개"], "summary": "한 문장 요약(40자 이내)"}
                """;

        assertThat(LlmPrompt.system(PromptVersion.V1)).isEqualTo(expected);
        assertThat(LlmPrompt.system(PromptVersion.V1)).isEqualTo(LlmPrompt.SYSTEM);
    }
}
