-- 앱 휴지통에 있는 캡처. null이 아니면 관심사 집계·푸시에서 뺀다(되살리면 null). 행과 태그 연결은 그대로 둔다.
alter table screenshot add column trashed_at timestamp(6);
