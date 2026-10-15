# LLM 분류 실험 결과

- 실행일: 2026-10-15
- 표본: 43장
- **OCR은 앱의 ML Kit이 아니라 Tesseract(kor+eng) 결과라 근사치다.** 실제 앱 텍스트 품질과 다를 수 있다.
- 모든 후보가 같은 프롬프트(카테고리 7개 고정, JSON 응답)를 사용했다.
- 표본이 적어 카테고리별 수치는 편차가 크다. 순위보다 큰 격차와 실패 양상을 본다.

## 정확도

- **엄격**: `category`만 정답으로 인정. **허용**: `category` 또는 `alt`(허용 정답)이면 정답.
- **명확한 표본**: `alt`가 없는 표본만의 엄격 정확도. **애매한 표본**: `alt`를 적어 둔 표본 수.
- 호출 실패(통신 오류)는 모든 정확도 분모에서 제외한다.

| 후보 | 엄격 정확도 | 허용 정확도 | 명확한 표본 정확도 | 애매한 표본 수 |
|---|---|---|---|---|
| gemini-3.5-flash-lite | 45.0% (18/40) | 45.0% (18/40) | 50.0% (18/36) | 4 / 40장 |
| gemini-3.8-flash | 33.3% (4/12) | 33.3% (4/12) | 40.0% (4/10) | 2 / 12장 |

## 속도·비용

| 후보 | 평균 응답 | p95 응답 | 장당 비용(USD) | 1,000장 비용(USD) | 파싱 실패 | 호출 실패 |
|---|---|---|---|---|---|---|
| gemini-3.5-flash-lite | 1706 ms | 3042 ms | $0.000241 | $0.241 | 0 | 3 |
| gemini-3.8-flash | 4842 ms | 10435 ms | $0.001121 | $1.121 | 0 | 31 |

## 카테고리별 정확도 (엄격, 맞음/전체)

| 후보 | SHOPPING | ENTERTAINMENT | PLACE | INFO | CHAT | SCHEDULE | ETC |
|---|---|---|---|---|---|---|---|
| gemini-3.5-flash-lite | 7/15 | 1/1 | 1/3 | 8/20 | - | - | 1/1 |
| gemini-3.8-flash | 2/7 | - | 1/2 | 1/3 | - | - | - |

## 토큰 사용 (평균)

| 후보 | 입력 | 출력 |
|---|---|---|
| gemini-3.5-flash-lite | 462 | 41 |
| gemini-3.8-flash | 419 | 215 |

## 자주 틀린 조합 (정답→예측: 건수)

- gemini-3.5-flash-lite: SHOPPING→ETC: 6, INFO→ETC: 5, INFO→SHOPPING: 3, INFO→ENTERTAINMENT: 2, SHOPPING→INFO: 2
- gemini-3.8-flash: SHOPPING→ETC: 4, PLACE→ETC: 1, INFO→ENTERTAINMENT: 1, SHOPPING→INFO: 1, INFO→ETC: 1

> 오답 상세(파일명 포함)는 `errors.local.md`에 있으며 커밋되지 않는다.
