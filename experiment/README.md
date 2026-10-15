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
3. **정답 입력** — `labels.csv`의 `category` 칸을 아래 값 중 하나로 채운다. ([라벨링 기준](#라벨링-기준) 참고)
4. **API 키 설정** — Gemini만 지원한다 (PowerShell):
   ```
   $env:GEMINI_API_KEY = "..."
   ```
   키가 없으면 후보를 건너뛰고 빈 결과가 나온다.

   > **개인정보 주의**: Gemini API **무료 티어**에 보낸 입력은 Google 제품 개선에 쓰일 수 있다고 공식 문서에 명시돼 있다(유료 티어는 아님).
   > 스크린샷 OCR 텍스트는 개인 데이터이므로, 무료 티어로 보내도 괜찮은지 판단한 뒤 실행한다.
5. **첫 실행은 소량으로 형식 검증** (3장만 호출)
   ```
   cd server
   ./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.limit=3"
   ```
   콘솔에 건별로 `status`, 예측 카테고리, 토큰 수, 응답 시간, 모델 원문 앞부분이 출력된다.
   `status=OK`이고 토큰 수가 0이 아니면 요청·응답 형식이 맞는 것이다. 결과는 `results.limit.md`(커밋 안 됨)에 쓰고 `results.md`는 건드리지 않는다.
6. **전체 실행**
   ```
   ./gradlew bootRun --args="--spring.profiles.active=experiment"
   ```
   끝나면 `experiment/results.md`가 갱신된다. 오답 상세와 모델 원문은 `errors.local.md`(커밋 안 됨).

## 라벨링 기준
모델에게 주는 프롬프트의 카테고리 정의와 **동일한 문구**다. 이 기준으로 `labels.csv`를 채워야 정확도 비교가 공정하다.
(`LlmPrompt.DEFINITIONS`와 일치하는지 단위 테스트가 검사한다.)

| 값 | 포함하는 것 |
|---|---|
| `SHOPPING` | 상품, 가격, 구매, 장바구니, 배송. 가격·할인·장바구니·배송이 보이면 대개 SHOPPING |
| `ENTERTAINMENT` | 영화·드라마·OTT·연극·뮤지컬·공연·전시·책·음악 등 보고 싶은 작품·콘텐츠 |
| `PLACE` | 맛집·카페·팝업스토어·여행지 등 "가보고 싶은 곳" (운영 기간이 있어도 장소가 핵심이면 PLACE). 주소·영업시간·메뉴·위치가 보이면 대개 PLACE |
| `INFO` | 뉴스·꿀팁·방법 설명, 레시피·DIY·코디처럼 "알아두거나 따라 해보려는 것" |
| `CHAT` | 메신저·댓글 대화 |
| `SCHEDULE` | 일정, 예약, 티켓, 알림. 작품 자체가 아니라 날짜·예약·티켓 오픈이 핵심이면 SCHEDULE. 특정 날짜·시간, 예매 오픈, 예약 완료가 핵심이면 SCHEDULE |
| `ETC` | 위에 해당하지 않거나 의미 있는 글자가 없음 |

- 모델은 **OCR 텍스트만** 본다(이미지를 보지 않는다). 사진·그림 위주라 글자가 없거나 OCR이 거의 비면 `ETC`로 라벨링한다.
- 한 장이 여러 카테고리에 걸칠 때의 우선순위는 프롬프트에 **없다**. 라벨링할 때 임의 규칙을 만들지 말고, 정말 필요하면 프롬프트와 위 표를 함께 고친 뒤 실행한다.
- `category` 값은 영문 대문자 그대로 적는다(잘못된 값의 행은 건너뛴다).

### 애매한 표본: `alt`(허용 정답)
`labels.csv` 형식은 `filename,category,alt`이다. 경계가 정말 애매해서 두 카테고리 모두 정답이라고 볼 만한 표본에만 `alt`에 두 번째 카테고리를 적는다. 대부분의 행은 `alt`를 비워 둔다(`alt` 없는 2칸 형식도 그대로 읽힌다).

```
filename,category,alt
Screenshot_A.jpg,PLACE,SCHEDULE     # 팝업스토어: 장소가 핵심이지만 기간·예약도 핵심
Screenshot_B.jpg,SHOPPING,          # 명확 → alt 비움
```

`results.md`에는 모델별로 다음이 함께 표시된다.

| 지표 | 의미 |
|---|---|
| 엄격 정확도 | `category`만 정답으로 인정 |
| 허용 정확도 | `category` **또는** `alt`와 일치하면 정답 |
| 명확한 표본 정확도 | `alt`가 없는 표본만의 엄격 정확도 |
| 애매한 표본 수 | `alt`를 적은 표본 수 (많을수록 허용 정확도의 해석이 느슨해진다) |

- `alt`를 많이 쓰면 허용 정확도가 부풀려진다. 애매한 표본 수를 같이 보고, 순위는 **엄격**과 **명확한 표본** 정확도를 기준으로 본다.
- `alt`가 `category`와 같으면 애매한 표본으로 세지 않는다. 알 수 없는 값은 경고 후 무시한다.

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
