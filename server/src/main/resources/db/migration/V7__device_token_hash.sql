-- 기기 인증 토큰. 원문은 저장하지 않고 SHA-256(32바이트)만 둔다. 요청마다 이 해시로 기기를 찾는다.
-- 이 버전 전에 등록된 기기는 null이다: 토큰으로는 찾을 수 없고, 이전 창구(LegacyDeviceClaim)로 한 번만 받을 수 있다.
alter table device add column token_hash bytea;
alter table device add constraint uk_device_token_hash unique (token_hash);
