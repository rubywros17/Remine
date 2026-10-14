# LLM 분류 실험

2주차 `LlmClassifier` 선택을 위해 후보 LLM의 **분류 정확도 · 응답 속도 · 장당 비용**을 비교한다.

> `images/`, `ocr/`, `labels.csv`, `errors.local.md`는 개인 데이터라 `.gitignore`로 커밋하지 않는다.
> 커밋되는 것은 `results.md`(집계 수치만)와 이 폴더의 스크립트·설정뿐이다.

## 순서
1. **이미지 넣기** — `experiment/images/`에 스크린샷 30~50장.
2. **OCR** — Tesseract 설치(UB-Mannheim 빌드, 설치 중 Korean 데이터 체크) 후:
   ```
   bash experiment/ocr.sh
   ```
   `ocr/*.txt`와 `labels.csv` 템플릿이 생성된다.
3. **정답 입력** — `labels.csv`의 `category` 칸을 아래 값 중 하나로 채운다.

   | 값 | 의미 |
   |---|---|
   | `SHOPPING` | 쇼핑 |
   | `MOVIE_DRAMA` | 영화/드라마 |
   | `PLACE` | 맛집/장소 |
   | `INFO` | 정보/꿀팁 |
   | `CHAT` | 대화 |
   | `SCHEDULE` | 일정/예약 |
   | `ETC` | 기타 |
4. **API 키 설정** — Gemini만 지원한다 (PowerShell):
   ```
   $env:GEMINI_API_KEY = "..."
   ```
   키가 없으면 후보를 건너뛰고 빈 결과가 나온다.

   > **개인정보 주의**: Gemini API **무료 티어**에 보낸 입력은 Google 제품 개선에 쓰일 수 있다고 공식 문서에 명시돼 있다(유료 티어는 아님).
   > 스크린샷 OCR 텍스트는 개인 데이터이므로, 무료 티어로 보내도 괜찮은지 판단한 뒤 실행한다.
5. **실행**
   ```
   cd server
   ./gradlew bootRun --args='--spring.profiles.active=experiment'
   ```
   끝나면 `experiment/results.md`가 갱신된다. 오답 상세는 `errors.local.md`(커밋 안 됨).

## 후보 / 가격
`candidates.json`에 모델 ID와 단가(USD / 1M tokens)를 둔다. 가격이 바뀌면 이 파일만 고치면 된다.
공식 가격 페이지 기준(2026-10-14):

| 후보 | 입력 / 출력 (USD/1M) | 무료 티어 | 비고 |
|---|---|---|---|
| `gemini-3.5-flash-lite` | 0.30 / 2.50 | 있음 | Flash-Lite, 사고 기본 minimal |
| `gemini-3.8-flash` | 0.75 / 3.75 | 있음 | 일반 Flash, 사고 기본 medium. **2027-01-01부터 1.50 / 7.50으로 인상 예정** |

- 사고(thinking) 토큰은 출력 토큰으로 과금된다. 결과의 "출력 토큰"과 장당 비용에는 사고 토큰이 포함된다.
- 무료 티어의 숫자 한도는 문서에 없고 AI Studio에서 확인한다. 한도에 걸리면 호출 실패로 집계된다.

## 한계
- OCR은 앱의 ML Kit이 아니라 Tesseract라서 **근사치**다. 실제 앱의 텍스트 품질과 다르다.
- 표본이 30~50장이라 카테고리별 수치는 편차가 크다. 순위보다 큰 격차·실패 양상을 본다.
