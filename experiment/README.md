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
4. **API 키 설정** — 가진 제공사만 (PowerShell):
   ```
   $env:ANTHROPIC_API_KEY = "..."
   $env:GEMINI_API_KEY    = "..."
   $env:OPENAI_API_KEY    = "..."
   ```
   키가 없는 제공사의 후보는 자동으로 건너뛴다.
5. **실행**
   ```
   cd server
   ./gradlew bootRun --args='--spring.profiles.active=experiment'
   ```
   끝나면 `experiment/results.md`가 갱신된다. 오답 상세는 `errors.local.md`(커밋 안 됨).

## 후보 / 가격
`candidates.json`에 모델 ID와 단가(USD / 1M tokens)를 둔다. 가격이 바뀌면 이 파일만 고치면 된다.

## 한계
- OCR은 앱의 ML Kit이 아니라 Tesseract라서 **근사치**다. 실제 앱의 텍스트 품질과 다르다.
- 표본이 30~50장이라 카테고리별 수치는 편차가 크다. 순위보다 큰 격차·실패 양상을 본다.
