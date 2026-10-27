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
