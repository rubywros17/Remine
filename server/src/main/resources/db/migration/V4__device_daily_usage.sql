-- 예전 스크린샷(기기 등록 전에 찍힌 캡처) 기기별 하루 분석 수. 날짜는 한국 시간(KST) 기준이라 자정에 새 행으로 초기화된다.
-- 분석 전에 예약하고, 분석에 실패한 장은 다시 빼서(환불) 성공한 장만 남는다.
create table device_daily_usage (
    device_id   bigint  not null,
    usage_date  date    not null,
    older_count integer not null default 0,
    constraint pk_device_daily_usage primary key (device_id, usage_date),
    constraint fk_device_daily_usage_device foreign key (device_id) references device (id) on delete cascade
);
