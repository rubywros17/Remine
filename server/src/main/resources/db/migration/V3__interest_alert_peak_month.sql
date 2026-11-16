-- 잊고 있었던 관심사 알림 문구("9월에 'X'를 12번이나 캡처했어요")의 근거. 요즘 관심사 알림이면 둘 다 null.
alter table interest_alert add column peak_month integer;
alter table interest_alert add column peak_month_count integer;
