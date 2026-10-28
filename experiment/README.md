# LLM 분류 실험

2주차 `LlmClassifier` 선택을 위해 후보 LLM의 **분류 정확도 · 응답 속도 · 장당 비용**을 비교한다.

> `images/`, `ocr/`, `labels.csv`, `errors.local.*.md`는 개인 데이터라 `.gitignore`로 커밋하지 않는다.
> 커밋되는 것은 `results.md`(집계 수치만)와 이 폴더의 스크립트·설정뿐이다.

> 10/15 이전에 만든 결과 파일(`results.*.md`)의 개인정보 원칙 문구("서비스 경로는 이미지를 서버로 보내지 않는다" 등)는 **당시 기준**이며 보존한다. 현재 원칙은 [docs/spec.md](../docs/spec.md)의 개인정보 원칙을 참고한다.

## 순서
1. **이미지 넣기** — `experiment/images/`에 스크린샷 30~50장.
2. **OCR** — Tesseract 설치(UB-Mannheim 빌드, 설치 중 Korean 데이터 체크) 후:
   ```
   bash experiment/ocr.sh
   ```
   `ocr/*.txt`와 `labels.csv` 템플릿이 생성된다.
3. **정답 입력** — `labels.csv`의 `category` 칸을 아래 값 중 하나로 채운다. ([라벨링 기준](#라벨링-기준) 참고)
4. **API 키 설정** — Gemini만 지원한다. 러너는 스프링 설정(Environment)에서 `GEMINI_API_KEY`를 읽으므로 방법이 두 가지다.
   - **파일(권장, 셸마다 export 불필요)**: 환경변수 `REMINE_ENV_FILE`이 가리키는 파일(예: `E:\dev\secrets\remine\remine.env`), 없으면 사용자 홈의 `~/.remine.env`(Windows: `C:\Users\<이름>\.remine.env`)에 한 줄을 적는다.
     ```
     GEMINI_API_KEY=키값
     ```
     따옴표나 `export`를 붙이지 않고, **BOM 없는 UTF-8**로 저장한다(메모장의 "UTF-8(BOM 포함)"으로 저장하면 첫 줄 이름이 깨져 키가 없는 것으로 읽힌다).
     파일은 레포 밖이라 커밋되지 않는다. 공통 설정(`application.yaml`의 `spring.config.import`)에서 읽으며 파일이 없어도 기동한다.
   - **환경변수**: `export GEMINI_API_KEY=키값`(Git Bash) 또는 `$env:GEMINI_API_KEY = "키값"`(PowerShell). 환경변수가 있으면 파일보다 **우선**한다.

   키가 없거나 비어 있으면 표본을 읽거나 API를 부르기 **전에** 오류 로그를 남기고 바로 끝나며 어떤 파일도 쓰지 않는다.
   로그와 결과 파일에는 키 값이나 길이를 남기지 않고 "후보 N개 중 M개에 키가 있습니다"만 출력한다.

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
   끝나면 `experiment/results.prompt-v1.md`가 갱신된다. 오답 상세와 모델 원문은 실행 시각이 붙은 `errors.local.20261015-1426.md` 같은 파일에 매번 새로 저장된다(커밋 안 됨, 이전 실행 기록을 덮어쓰지 않음).
   평가한 후보가 0개(API 키 없음 등)이면 결과 파일을 **아무것도 쓰지 않으므로** 이전 결과가 지워지지 않는다.

   **호출이 대부분 실패한 실행은 결과로 인정하지 않는다.** 실제로 API를 부른 표본 중 호출 실패가 **10%를 넘으면** 그 후보는 결과 표와
   `runs/`(실행 기록)에 들어가지 않고 "제외한 후보"로 표시된다. 잘못된 키처럼 다시 시도해도 소용없는 실패(또는 서버가 120초 넘게 기다리라는 쿼터 소진)가
   **연속 3건** 나오면 그 후보는 바로 중단한다(43장을 끝까지 돌며 시간과 호출을 낭비하지 않는다). 원인은 오답 상세 파일의 "호출 실패" 줄에 상태 코드와 메시지로 남는다.

## 배치 비교 (`--experiment.batch`)
운영 하이브리드(OCR 150자 미만이면 이미지 포함)를 여러 장씩 한 요청으로 묶었을 때 정확도가 떨어지지 않는지 본다.
```
./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.batch=10,5"   # 텍스트 10장 · 이미지 5장씩
./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.batch=1,1"    # 같은 경로의 단건 기준선
```
결과는 `compare.local.batch-<텍스트>-<이미지>.<시각>.md`(커밋 안 됨)에만 쓰고 `results.*.md`·`runs/`는 건드리지 않는다.
머리말에 LLM 호출 수·단건 재시도 수·토큰 합계·비용이 붙는다. 채택 기준: 두 번 실행해 둘 다 단건 하이브리드 기존 측정의 하한(33/43) 이상.

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

### 프롬프트 v2 경계 규칙
> **채택 안 됨 (사유: SHOPPING 회귀).** v2는 실험 옵션으로만 남기며 기본값과 운영 프롬프트는 **v1**이다.
> 같은 43장에서 하이브리드 정확도가 −3장(편차 기준선 −1장)이었고, 이미지 후보의 SHOPPING→INFO 오답이 3 → 8건으로 늘었다.
> 규칙 1("구매 단서가 있어야 SHOPPING")이 카테고리 정의("가격·할인·장바구니·배송이 보이면 대개 SHOPPING")와 충돌한 것이 원인으로 판단된다.
> 근거와 수치는 [`SUMMARY.md`](SUMMARY.md)의 "프롬프트 v2 실험"과 `results.compare.prompt-v1-vs-prompt-v2.md`에 있다.

`--experiment.prompt=v2`는 위 카테고리 정의는 그대로 두고, 경계가 애매할 때 정의보다 우선하는 아래 규칙 두 개를 프롬프트에 더한다.
**정의가 바뀌지 않으므로 `labels.csv`는 다시 만들지 않으며** v1과 같은 정답으로 비교한다. 규칙은 일반 원칙만 담고 특정 캡처·앱을 겨냥하지 않는다.
(`LlmPrompt.RULES_V2`와 일치하는지 단위 테스트가 검사한다.)

- SHOPPING은 구매 의도가 보일 때만 고른다. 가격·구매 버튼·장바구니·주문처럼 사는 행동으로 이어지는 단서가 있어야 하며, 가격이나 상품이 보여도 정보를 전달하는 내용(소개·비교·팁·후기 정리)이 중심이면 INFO를 고른다.
- 게시·작성·업로드 날짜(예: "2시간 전", 게시일)는 일정이 아니다. SCHEDULE은 앞으로 갈 날짜·시간과 함께 해야 할 일, 장소, 예약이 같이 있을 때만 고른다.

라벨링할 때 이 규칙을 따로 적용할 필요는 없다(정의 기준으로 이미 라벨링했다). 규칙은 모델이 경계 사례에서 정의를 어떻게 적용할지만 좁힌다.

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

- **temperature = 1.0 (두 후보 모두)**: Gemini 3 공식 문서가 "모든 Gemini 3 모델은 temperature를 기본값 1.0으로 유지하길 강하게 권장하며,
  1.0 미만으로 낮추면 반복(looping)이나 성능 저하가 생길 수 있다"고 하므로 권장값에 맞춘다.
  후보별로 `candidates.json`의 `"temperature"`로 바꿀 수 있고(코드 기본값은 0), 생략하면 0이 전송된다.
  - 대가: temperature 1.0에서는 같은 입력도 실행마다 결과가 조금씩 달라질 수 있다. 정확도 차이가 몇 장 수준이면 재실행 편차일 수 있으니 순위를 단정하지 않는다.
  - 1차 실행(`results.v1-baseline.md`)은 temperature 전송 기능이 생기기 **전**에 돌려서 요청에 값이 없었다(모델 기본값).
- 사고(thinking) 토큰은 출력 토큰으로 과금된다. 결과의 "출력 토큰"과 장당 비용에는 사고 토큰이 포함된다.
- 무료 티어의 숫자 한도는 문서에 없고 AI Studio에서 확인한다. 한도에 걸리면 호출 실패로 집계된다.

### 호출 실패(429) 대응
1차 실행에서 43장 중 `gemini-3.8-flash`는 31건, `gemini-3.5-flash-lite`는 3건이 호출 실패였고, 원인은 대부분 **HTTP 429**("You exceeded your current quota")였다.
(나머지 1건은 503 `high demand`.)

- **재시도**: 429, 5xx, 통신 오류만 최대 5회 재시도한다. 400·401·403·404는 다시 해도 같으므로 재시도하지 않는다.
- **대기**: 서버가 알려 준 시간(`Retry-After` 헤더 또는 응답 본문의 `RetryInfo.retryDelay`)이 있으면 그 시간 + 1초를 기다리고,
  없으면 지수 백오프(2s → 4s → 8s → 16s, 최대 60s)를 쓴다. 서버가 **120초보다 오래** 기다리라고 하면(일일 한도 소진 등) 기다리지 않고 그 표본을 호출 실패로 둔다.
- **호출 간격**: `candidates.json`의 후보별 `minIntervalMs`로 연속 호출 시작 사이 최소 간격을 지정한다. 처음부터 속도 제한 아래로 보내 429를 피하는 용도다.
  현재 값(`3.5-flash-lite` 4500ms, `3.8-flash` 13000ms)은 **AI Studio 확인값(2026-10-15)** 인 무료 등급 RPM(flash-lite 15, flash 5)을 넘지 않게 정한 값이며, 한도가 바뀌면 조정한다.
  간격 때문에 전체 실행 시간이 길어진다(43장 기준 3.8-flash 약 10분).
- **일일 한도(RPD)·토큰 한도(TPM)는 간격으로 못 막는다.** 그 경우 호출 실패가 계속되며, 원인은 `errors.local.*.md`의 "호출 실패" 줄에 상태 코드와 메시지로 남는다.
- 호출이 전부 실패해 평가된 표본이 없는 후보는 결과 표에서 빠지고(`건너뛴 후보`에 사유 표시), 호출을 시도했다면 실패 원인 파일만 남는다.

### 멀티모달 변형: `gemini-3.5-flash-lite+image`
`candidates.json`의 `"input"`이 `"text"`(기본) 또는 `"text+image"`다. `text+image` 후보는 같은 모델에 **OCR 텍스트와 원본 스크린샷**을 함께 보낸다.
텍스트 전용 후보와의 차이만 보려는 변형이라 모델·단가·temperature·시스템 프롬프트는 같다.

- **이미지 처리**: `images/`의 원본을 긴 변 **1024px**로 줄여(확대하지 않음) JPEG(품질 0.85)로 인코딩해 보낸다. 같은 이미지는 한 번만 줄여 재사용한다.
- **프롬프트 차이**: 시스템 프롬프트와 카테고리 정의는 같고, user 메시지 끝에 "이미지도 함께 참고하라"는 한 줄만 더한다. 텍스트는 이미지 앞에 둔다(문서 권장).
- **비용**: 비용은 API가 돌려주는 입력 토큰(`promptTokenCount`)에 이미지 토큰이 포함된 값으로 계산한다. 이미지는 텍스트와 같은 입력 단가다.
  문서 기준 이미지는 384px 이하면 258토큰, 더 크면 768px 타일당 258토큰이므로 텍스트 전용(평균 약 450토큰)보다 입력이 크게 늘어난다.
  `media_resolution`은 보내지 않고 모델 기본값을 쓴다(generateContent의 필드 형식을 문서에서 확인하지 못함).
- **글자 없는 스크린샷도 호출한다.** 텍스트 후보는 OCR이 비면 모델을 부르지 않고 ETC로 처리하지만, 이미지 후보는 이미지를 보고 분류해 볼 수 있어서 호출한다.
  두 후보의 정확도 차이에는 이 부분이 포함된다.
- **원본 이미지 전송은 실험 러너 전용**: 서비스 경로(앱 → 서버)는 원본을 보내지 않는다. 서비스는 동의한 경우에만 OCR이 짧은 캡처의 축소 이미지(긴 변 1024px)를 받고, 서버에 저장하지 않는다(현재 원칙은 spec 참고).
- **개인정보 주의**: 이미지는 OCR 텍스트보다 민감하다. 무료 티어 입력은 Google 제품 개선에 쓰일 수 있으므로,
  이미지 후보는 무료 티어로 개인 스크린샷을 보내도 괜찮은지 판단한 뒤 실행한다. 이미지 후보를 빼려면 `--experiment.candidates`로 텍스트 후보만 지정한다.
- 이미지 파일을 읽을 수 없으면 그 표본은 호출 실패로 집계된다.

### 프롬프트 버전
`--experiment.prompt=v1|v2`로 분류 프롬프트 버전을 고른다(**기본 v1**). 이전 버전은 지우지 않고 남겨 같은 표본에서 버전끼리 비교한다.
v2는 **채택되지 않았다**(SHOPPING 회귀, [위 절](#프롬프트-v2-경계-규칙) 참고). 재현·비교용 실험 옵션으로만 쓴다.
결과 파일명에 버전이 들어간다: 전체 실행은 `results.prompt-v2.md`, 후보 지정 실행은 `results.prompt-v2.gemini-3.5-flash-lite.md`.
**버전 접두어가 없는 기존 `results.*.md`는 프롬프트 버전 도입 전(v1)의 결과**이고, `results.v1-baseline.md`는 프롬프트 버전이 아니라 1차 실행(temperature 미전송)이라는 뜻이다.

### 프롬프트 버전 비교
전체 실행(`--experiment.limit` 없이)은 표본별 결과를 `experiment/runs/`(gitignore, 파일명 포함)에 남긴다.
같은 후보를 두 프롬프트 버전으로 각각 돌린 뒤, API 호출 없이 최신 실행끼리 비교한다.
```
./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.compare=v1,v2"
```
- `results.compare.prompt-v1-vs-prompt-v2.md`(커밋 가능, 파일명 없음): 전체·카테고리별·글자 수 구간별 정확도, 고쳐진 것/새로 틀린 것의 유형별 건수, 하이브리드(150자) 정확도.
- `compare.local.prompt-v1-vs-prompt-v2.md`(gitignore): 고쳐진/새로 틀린 표본의 파일명 목록.
- 텍스트 후보와 같은 모델의 `+image` 후보 실행이 둘 다 있으면 하이브리드를 표본별로 합산한다(SUMMARY의 하이브리드 76.7~79.1%와 같은 방식).
- temperature 1.0이라 같은 프롬프트도 실행마다 몇 장은 달라진다. 개선 폭을 해석하려면 같은 버전을 두 번 돌린 편차를 함께 본다.

### 특정 후보만 실행
```
./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.candidates=gemini-3.8-flash"
```
후보 이름 또는 모델 ID를 쉼표로 여러 개 줄 수 있다. **후보 이름과 정확히 같으면 그 후보만** 고른다:
`gemini-3.5-flash-lite`는 텍스트 후보만, `gemini-3.5-flash-lite+image`는 이미지 변형만이고, 둘 다 실행하려면 쉼표로 이어 쓴다.
후보 이름과 같지 않은 값은 모델 ID로 보고 같은 모델의 변형을 모두 고른다. 후보를 지정한 실행은 다른 후보의 기존 `results.md`를 지우지 않도록
`results.gemini-3.8-flash.md`처럼 **후보 이름이 붙은 파일**에 쓴다(집계 수치만 있어 커밋해도 된다). `--experiment.limit`와 같이 쓰면 `results.limit.md`에 쓴다.

## 오답 분석 지표
`results.md`의 "오답 분석: 평균 OCR 글자 수"는 모델별로 **정답 / 오답 / ETC로 예측한 오답**의 평균 OCR 글자 수(공백 제외)를 보여준다.

- 정답·오답은 허용 기준(`category` 또는 `alt` 일치)이다. 호출 실패 표본은 제외한다.
- 오답의 글자 수가 정답보다 뚜렷이 적고, 특히 "ETC로 예측한 오답"의 글자 수가 매우 적다면 모델이 아니라 **OCR 품질·글자량**이 원인일 가능성이 크다.
  반대로 글자가 충분한데 ETC로 예측했다면 프롬프트 정의나 모델 판단을 의심한다.
- 글자가 없어 모델을 부르지 않고 ETC로 처리한 표본은 0자로 "ETC로 예측한 오답"(정답이 ETC가 아닌 경우)에 들어간다.

## ML Kit 기준 OCR 재측정 (폰)

위 순서의 OCR은 Tesseract라 실제 앱(ML Kit)과 다르다. 같은 43장을 폰의 ML Kit(한국어, 기기 안·오프라인)으로 다시 돌려 글자 수·텍스트를 비교한다. 이미지·OCR 원문은 PC와 폰 사이에서만 오가고 어떤 서버로도 나가지 않는다.

1. **폰에 올리기** — Screenshots 폴더가 아니라 **별도 폴더**에 넣어 실제 스크린샷과 섞이지 않게 한다. (USB 디버깅 연결)
   ```
   adb push experiment/images /sdcard/Pictures/RemineExperiment
   adb shell content call --uri content://media/external/file --method scan_volume --arg external_primary
   ```
   두 번째 줄은 갤러리가 새 사진을 인식하게 하는 미디어 스캔이다(기기에 따라 갤러리 앱을 한 번 열어야 잡히기도 한다).
2. **앱 실행(디버그 빌드, 기기 모드)** — `cd app && flutter run -d <id> --dart-define=DATA=device`
   사진 권한을 허용하고, 홈 화면 맨 위 `re:mine` 워드마크를 **길게 누르면** "OCR 측정 (디버그)" 화면이 열린다. (릴리스 빌드에는 이 화면이 없다)
3. **측정** — 위쪽 앨범 칩에서 `RemineExperiment` 선택 → [전체 선택] → [OCR 실행] → 끝나면 [JSON 내보내기].
   앨범 칩에는 `Screenshots`(실제 스크린샷)도 있다. 확장 표본은 같은 방법으로 폴더를 하나 더 만들어 넣는다.
4. **PC로 가져오기**
   ```
   mkdir -p experiment/mlkit
   adb pull /sdcard/Android/data/com.remine.remine/files/ experiment/mlkit/
   ```
5. **비교** — `python experiment/compare_mlkit.py` → `compare.local.mlkit-vs-tesseract.md`
   (파일별 글자 수, 150자 기준을 가로지르는 장 수. `--show-text`를 주면 앞 60자도 적는다)
6. **측정 후 지우기** — OCR 원문이 폰과 PC에 남지 않게 정리한다.
   ```
   adb shell rm -r /sdcard/Pictures/RemineExperiment
   adb shell content call --uri content://media/external/file --method scan_volume --arg external_primary
   adb shell rm /sdcard/Android/data/com.remine.remine/files/ocr-export-*.json
   ```
   앱 안에 저장된 OCR 결과는 측정 화면의 [저장된 결과 지우기], 또는 `adb shell pm clear com.remine.remine`(앱 데이터 전체 삭제)로 지운다. PC의 `experiment/mlkit/`도 비교가 끝나면 지운다.

7. **분류 재측정** — OCR만 ML Kit으로 바꿔 같은 분류 실험(프롬프트 v1, 같은 `labels.csv`)을 돌린다. 실행 기록은 `runs-mlkit/`(gitignore)에 따로 남아 Tesseract 기록·`--experiment.compare`와 섞이지 않는다.
   ```
   cd server
   ./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.ocr=mlkit --experiment.mlkit-json=../experiment/mlkit/files/ocr-export-20261021-152141.json --experiment.candidates=gemini-3.5-flash-lite,gemini-3.5-flash-lite+image"
   ```
   결과: `results.mlkit.prompt-v1.*.md`, Tesseract 대비 `results.mlkit-vs-tesseract.<모델>.md`(집계, 커밋 가능), 150자 기준이 바뀐 장 목록 `compare.local.mlkit-remeasure.md`(gitignore).

> `experiment/mlkit/`, `ocr-export-*.json`, `compare.local.mlkit-vs-tesseract.md`에는 **OCR 원문이 들어 있어** `.gitignore`로 커밋하지 않는다(위 개인 데이터 규칙과 같다).

## 한계
- OCR은 앱의 ML Kit이 아니라 Tesseract라서 **근사치**다. 실제 앱의 텍스트 품질과 다르다.
- 표본이 30~50장이라 카테고리별 수치는 편차가 크다. 순위보다 큰 격차·실패 양상을 본다.
