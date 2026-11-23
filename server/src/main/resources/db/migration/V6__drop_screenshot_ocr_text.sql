-- OCR 원문은 분류(LLM 입력)에만 쓰고 서버가 다시 읽지 않으므로 저장하지 않는다(데이터 최소화).
-- 값을 먼저 비운 뒤 컬럼을 지운다. PostgreSQL은 DROP COLUMN·UPDATE 뒤에도 예전 값이 데이터 파일에 남으므로
-- 배포 후 운영 DB에서 VACUUM FULL screenshot; 을 1회 실행해 표를 다시 쓴다(트랜잭션 안에서는 못 돌려 여기 넣지 않음).
update screenshot set ocr_text = null where ocr_text is not null;
alter table screenshot drop column ocr_text;
