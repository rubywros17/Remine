-- 서버 전체 하루 LLM 호출 수(Gemini 무료 등급 하루 요청 한도 보호용). 날짜는 태평양 시간(America/Los_Angeles) 기준:
-- Gemini 무료 한도가 태평양 시간 자정에 초기화되기 때문이다(서머타임 자동 반영). 성공한 호출만 남는다.
-- older_calls: 예전 스크린샷 분류 호출(예산의 일부까지만), new_calls: 새 스크린샷 분류 호출(막지 않고 기록만).
create table llm_daily_usage (
    usage_date  date    not null,
    older_calls integer not null default 0,
    new_calls   integer not null default 0,
    constraint pk_llm_daily_usage primary key (usage_date)
);
