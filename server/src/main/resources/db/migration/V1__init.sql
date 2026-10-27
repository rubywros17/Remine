-- 초기 스키마. 엔티티(domain/*)와 1:1이며 ddl-auto=validate가 기동 때 맞는지 확인한다.
-- 이 파일은 적용된 뒤 고치지 않는다. 스키마 변경은 V2__*.sql부터 새 파일로.
--
-- H2 시절의 데이터는 옮기지 않는다(인메모리라 남은 게 없음). 그래서 spec 8장 "운영 DB 전환 메모"의
-- 백필·태그 병합 단계 없이 최종 형태로 만든다: tag.normalized_name unique(name은 unique 아님),
-- auto_category·category_source 포함, enum 컬럼은 CHECK.

-- ID는 SEQUENCE(allocationSize 50 = increment 50). Hibernate가 50개씩 미리 받아 INSERT를 배치로 보낸다.
create sequence device_seq start with 1 increment by 50;
create sequence screenshot_seq start with 1 increment by 50;
create sequence tag_seq start with 1 increment by 50;
create sequence screenshot_tag_seq start with 1 increment by 50;
create sequence interest_alert_seq start with 1 increment by 50;

create table device (
    id         bigint       not null,
    fcm_token  varchar(255),
    created_at timestamp(6) not null,
    constraint pk_device primary key (id)
);

create table screenshot (
    id              bigint       not null,
    device_id       bigint       not null,
    local_asset_id  varchar(255) not null,
    taken_at        timestamp(6) not null,
    source_app      varchar(255),
    ocr_text        text,
    category        varchar(255),
    auto_category   varchar(255),
    category_source varchar(255),
    summary         varchar(255),
    analyzed_at     timestamp(6),
    constraint pk_screenshot primary key (id),
    constraint fk_screenshot_device foreign key (device_id) references device (id),
    constraint uk_screenshot_device_asset unique (device_id, local_asset_id),
    constraint ck_screenshot_category
        check (category in ('SHOPPING', 'ENTERTAINMENT', 'PLACE', 'INFO', 'CHAT', 'SCHEDULE', 'ETC')),
    constraint ck_screenshot_auto_category
        check (auto_category in ('SHOPPING', 'ENTERTAINMENT', 'PLACE', 'INFO', 'CHAT', 'SCHEDULE', 'ETC')),
    constraint ck_screenshot_category_source check (category_source in ('AUTO', 'USER'))
);

-- 기기별 최신순 목록 조회용
create index ix_screenshot_device_taken_at on screenshot (device_id, taken_at);

create table tag (
    id              bigint       not null,
    name            varchar(255) not null,
    normalized_name varchar(255) not null,
    constraint pk_tag primary key (id),
    constraint uk_tag_normalized_name unique (normalized_name)
);

create table screenshot_tag (
    id            bigint not null,
    screenshot_id bigint not null,
    tag_id        bigint not null,
    constraint pk_screenshot_tag primary key (id),
    constraint fk_screenshot_tag_screenshot foreign key (screenshot_id) references screenshot (id),
    constraint fk_screenshot_tag_tag foreign key (tag_id) references tag (id),
    constraint uk_screenshot_tag unique (screenshot_id, tag_id)
);

-- PostgreSQL은 FK에 인덱스를 만들지 않는다. screenshot_id 쪽은 위 unique가 맡고,
-- tag_id로 거는 조회(태그 필터·관심사 집계)는 이 인덱스를 쓴다.
create index ix_screenshot_tag_tag on screenshot_tag (tag_id);

create table interest_alert (
    id            bigint       not null,
    device_id     bigint       not null,
    tag_id        bigint       not null,
    category      varchar(255) not null,
    capture_count integer      not null,
    week_start    date         not null,
    status        varchar(255) not null,
    created_at    timestamp(6) not null,
    sent_at       timestamp(6),
    constraint pk_interest_alert primary key (id),
    constraint fk_interest_alert_device foreign key (device_id) references device (id),
    constraint fk_interest_alert_tag foreign key (tag_id) references tag (id),
    constraint uk_interest_alert_device_week unique (device_id, week_start),
    constraint ck_interest_alert_category
        check (category in ('SHOPPING', 'ENTERTAINMENT', 'PLACE', 'INFO', 'CHAT', 'SCHEDULE', 'ETC')),
    constraint ck_interest_alert_status check (status in ('PENDING', 'SENT', 'EXPIRED'))
);
