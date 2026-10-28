# 📸 Remine

> 잊은 캡처, 다시 꺼내드릴게요

나중에 보려고 찍어두고 잊어버린 스크린샷을 자동으로 분류해 보여주고,
자주 캡처했던 **잊은 관심사**를 먼저 꺼내서 알려주는 앱입니다.

**Remine** = **re** (다시) + **mine** (캐내다 / 내 것) — 묵혀둔 캡처를 다시 캐내서, 다시 내 것으로.

> **민감한 캡처는 기기를 떠나지 않고, 분석용 이미지는 동의한 경우에만 보내며 서버에 저장하지 않는다.**

---

## ✨ MVP 기능

| 기능 | 설명 |
|---|---|
| 스크린샷 불러오기 | 갤럭시 앨범의 Screenshots 폴더를 자동으로 수집 |
| 기기 내 OCR | ML Kit 한국어 인식. 민감 정보 필터와 은행·메신저 앱 분류도 기기에서 처리 |
| AI 분류 | LLM으로 카테고리 · 태그 · 한 줄 요약 생성, 사용자가 카테고리 수정 가능 |
| 정리 화면 | 카테고리 카드 · 이미지 그리드 · 태그 필터 |
| 잊은 관심사 알림 | 태그 빈도를 집계해 반복된 관심사를 주 1회 푸시로 알림 |

## 🏗️ 아키텍처

```
[Flutter 앱]
  기기 내 OCR (ML Kit) → 민감 정보 필터 → 앱 기반 분류
  (민감·은행·증권·메신저 캡처는 기기에서 끝남, 전화번호는 [전화번호]로 가림)
      │
      │  OCR 텍스트 + 메타데이터
      │  + (OCR 150자 미만이고 동의한 경우에만) 긴 변 1024px 축소 이미지
      ▼
[Spring Boot 서버] ── 텍스트(+ 이미지) ──▶ [Gemini]
  이미지는 메모리에서 전달만 하고 저장하지 않음
  저장: OCR 텍스트 · 카테고리 · 태그 · 요약 · 메타데이터   ──▶ [DB]
      │
      └── 관심사 집계 ──▶ FCM 푸시 ──▶ 앱
```

## 🛠️ Tech Stack

| 영역 | 기술 |
|---|---|
| App | Flutter (Dart), photo_manager, Google ML Kit |
| Backend | Spring Boot 4.1.1, Java 21 |
| AI | Gemini `gemini-3.5-flash-lite` (temperature 1.0) |
| DB | PostgreSQL 17, Flyway (로컬은 Docker Compose) |
| Push | Firebase Cloud Messaging |

## 📊 Key Numbers

| 지표 | 결과 | 조건 |
|---|---|---|
| 첫 분석 시간 | **약 20분 → 4.6분** (1,197초 → 279초) | 갤럭시 실기기, 최근 300장 중 서버 분석 265장 |
| LLM 호출 수 | **265 → 53회 (−80%)** | 같은 265장 |
| 장당 LLM 비용 | $0.00047 → **약 $0.0004 (−9%)** | Gemini 유료 단가 환산(개발은 무료 등급) |
| 분류 정확도 | **79.1% (34/43)** | 직접 라벨링한 표본 43장 |
| analyze 저장 SQL | **916 → 29회** | 300장, ID `IDENTITY` → `SEQUENCE` + JDBC 배치 |

- **배치 효과는 속도와 호출 수입니다.** 여러 장을 한 LLM 요청에 담아(텍스트 10장, 이미지 5장) 호출 수와 호출 간격 대기가 줄었습니다. 비용은 −9%에 그칩니다: 공통 프롬프트를 나눠 써 입력 토큰은 26% 줄지만 출력 토큰이 44% 늘고, 출력 단가가 입력의 8배 이상입니다.
- **배치로 정확도가 떨어지지 않는지** 같은 43장으로 확인했습니다: 단건 기준선 33/43, 배치 35·34/43, 요약 형식을 바꾼 프롬프트 v3 + 배치 34/43.

<details>
<summary>측정 조건 · 재현 방법</summary>

- **전**: 앱 요청당 5장 + 서버 배치 끔(장당 1호출). **후**: 앱 요청당 20장 + 서버 배치(텍스트 10 · 이미지 5). 둘 다 프롬프트 v3, 호출 간격 `min-interval-ms` 4500, 앱 데이터 삭제(새 기기 등록) 후 첫 동기화.
- 265장 = 갤러리 최근 300장 − 앱 자기 캡처 30장 − 기기 안에서 끝난 캡처(민감 정보·앱 기반) 5장. 전/후 모두 서버가 265장을 받았고 실패 0건.
- 시간은 서버의 첫 analyze 요청 시작 ~ 마지막 요청 끝(요청 사이 앱의 기기 내 OCR 포함). 가장 긴 요청은 20장 기준 21.8초(앱 타임아웃 2분).
- 비용은 Gemini 응답 `usageMetadata` 토큰 × 단가(`GeminiPricing`, gemini-3.5-flash-lite 유료 Standard, 2026-10-27 확인).
- 정확도 표본은 Tesseract OCR 근사(앱은 ML Kit)이고 1인 라벨링 43장입니다. 실사용 정확도는 `GET /api/categories/accuracy`(사용자 수정률)로 따로 잽니다.

```bash
# 서버 (dev 프로필이면 GET/DELETE /api/dev/metrics가 열린다)
./gradlew bootRun --args="--spring.profiles.active=dev --remine.classifier=gemini --remine.llm.batch.text-size=1 --remine.llm.batch.image-size=1"  # 전
./gradlew bootRun --args="--spring.profiles.active=dev --remine.classifier=gemini"                                                               # 후
curl -X DELETE localhost:8080/api/dev/metrics            # 측정 전 초기화

# 앱 (새 기기로 첫 동기화, 디버그 화면 [지금 동기화])
adb shell pm clear com.remine.remine
flutter run -d <id> --dart-define=DATA=device --dart-define=API_BASE=http://localhost:8080 \
  --dart-define=AUTO_SYNC=false --dart-define=SYNC_BATCH_SIZE=5   # 전만 SYNC_BATCH_SIZE=5, 후는 빼면 20장
curl localhost:8080/api/dev/metrics                      # 요청 수·호출 수·토큰·비용·시간

# 정확도 (43장 라벨 표본, 결과 파일은 커밋하지 않음)
./gradlew bootRun --args="--spring.profiles.active=experiment --experiment.prompt=v3 --experiment.batch=10,5"
```
</details>

## 🧭 주요 결정

- **모델과 입력 방식은 실험으로 정했습니다.** 본인 스크린샷 43장으로 비교한 결과, 텍스트만 41.9~44.2%, 텍스트+이미지 74.4%, 하이브리드(OCR 150자 기준) 76.7~79.1%였습니다. 하이브리드는 150자 이상 캡처(약 23%)에 이미지를 보내지 않아 전송량과 개인정보 노출도 줄입니다. 근거와 한계는 [experiment/SUMMARY.md](experiment/SUMMARY.md)에 있습니다.
- **프롬프트 v2는 채택하지 않았습니다.** 경계 규칙을 더한 v2가 하이브리드 정확도를 69.8%로 떨어뜨려(−3장) v1을 유지했습니다.
- **이미지는 서버에 흔적을 남기지 않습니다.** multipart를 메모리에서만 처리하고(임시 파일 없음), 재인코딩으로 EXIF·GPS를 제거하며, 로그·DB에 남지 않는 것을 실제 Tomcat 통합 테스트로 검증합니다.
- **한계:** 표본이 43장(1인 라벨링)으로 작습니다. 실험 OCR은 한글 UI 인식이 약한 Tesseract 근사치이고 실제 앱은 기기 내 ML Kit이라, 3주차에 재측정할 예정입니다.

## 🚧 현재 상태

| 영역 | 상태 |
|---|---|
| 서버: 분류(Gemini 하이브리드), 이미지 입력, 목록·요약, 카테고리 수정 | 구현됨 |
| 서버: 관심사 집계 · FCM 푸시 · PostgreSQL | 구현됨 |
| Flutter 앱 | 미착수 |

### API

| Method | Path | 설명 |
|---|---|---|
| POST | `/api/devices` | 기기 등록 |
| GET | `/api/config` | 분석 설정(이미지 기준값·크기 상한 등) |
| POST | `/api/screenshots/analyze` | OCR 텍스트(+ 이미지) 배치 분류, JSON 또는 multipart |
| GET | `/api/screenshots` | 분류된 스크린샷 목록 (카테고리·태그 필터, 페이지) |
| GET | `/api/categories/summary` | 홈 화면용 카테고리별 개수·대표 태그·최신 캡처 |
| PATCH | `/api/screenshots/{id}/category` | 사용자 카테고리 수정 |
| GET | `/api/categories/accuracy` | 실사용 분류 정확도(수정률·검토 기준 정확도·혼동 쌍) |

요청·응답 형식과 오류 규칙은 [docs/spec.md](docs/spec.md)의 API 절을 참고하세요. 예정: `GET /api/interests`.

## 📁 Structure

```
app/         Flutter 앱 (Android 우선, 예정)
server/      Spring Boot 서버
docs/        기획 · 설계 문서
experiment/  LLM 분류 실험 (요약, 설정, 집계 결과)
```

## ▶️ Run

Docker가 필요합니다. DB 비밀번호는 레포 밖 키 파일(`REMINE_ENV_FILE`, 없으면 `~/.remine.env`)에 `REMINE_DB_PASSWORD=값`으로 둡니다.

```bash
# 1. PostgreSQL (데이터는 볼륨에 남음, 지우려면 docker compose down -v)
docker compose --env-file "$REMINE_ENV_FILE" up -d

# 2. 서버 (기동 때 Flyway가 스키마를 맞춤)
cd server
./gradlew bootRun                                       # fake 분류기 (키 불필요)
./gradlew bootRun --args="--remine.classifier=gemini"   # 실제 Gemini (GEMINI_API_KEY 필요)

# 테스트 (Testcontainers가 PostgreSQL을 따로 띄움, Docker만 켜져 있으면 됨)
./gradlew test
```

배포 때 DB 접속 정보는 `SPRING_DATASOURCE_URL` · `SPRING_DATASOURCE_USERNAME` · `SPRING_DATASOURCE_PASSWORD`로 덮어씁니다.

## 📄 Docs

- [서비스 기획서](docs/spec.md)
- [LLM 분류 실험 요약](experiment/SUMMARY.md)
