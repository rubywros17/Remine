# 📸 Remine

[![server](https://github.com/rubywros17/Remine/actions/workflows/deploy.yml/badge.svg)](https://github.com/rubywros17/Remine/actions/workflows/deploy.yml) [![app](https://github.com/rubywros17/Remine/actions/workflows/app.yml/badge.svg)](https://github.com/rubywros17/Remine/actions/workflows/app.yml)

> 잊은 캡처, 다시 꺼내드릴게요

나중에 보려고 찍어두고 잊어버린 스크린샷을 자동으로 분류해 보여주고,
자주 캡처했던 **잊은 관심사**를 먼저 꺼내서 알려주는 앱입니다.

**Remine** = **re** (다시) + **mine** (캐내다 / 내 것) — 묵혀둔 캡처를 다시 캐내서, 다시 내 것으로.

> **민감한 캡처는 기기를 떠나지 않고, 분석용 이미지는 동의한 경우에만 보내며 서버에 저장하지 않는다.**

---

<!-- 시연 GIF 자리: 첫 분석 → 홈 → 머릿속 지도 → 관심사 → 정리 탭 -->

## ✨ 주요 기능

| 기능 | 설명 |
|---|---|
| 첫 분석 | 최신 300장을 기기에서 OCR하고 서버에서 분류. 카드가 카테고리 서랍으로 들어가는 진행 화면 |
| 기기 내 OCR · 개인정보 필터 | ML Kit 한국어 인식. 민감 정보·금융·메신저 캡처는 기기에서 끝나고 서버로 가지 않음 |
| AI 분류 | Gemini로 카테고리 7종 · 태그 · 한 줄 요약. 사용자가 고친 카테고리는 재분석이 덮어쓰지 않음 |
| 잊은 관심사 | 전체 기간에 3번 이상 캡처한 태그 = 관심사. 마지막 캡처가 30일 넘으면 **잊고 있었던 관심사**, 아니면 **요즘 모으는 중** |
| 머릿속 캡처 지도 | 관심사 탭 진입 시 뇌 윤곽 위에 키워드 칩과 연결선(같은 카테고리 실선, 같은 캡처 점선)을 그림 |
| 관심사 알림 | 주 1회, 잊고 있었던 관심사를 먼저 FCM 푸시: "9월에 '코바늘도안'을 12번이나 캡처했어요. 다시 볼까요?" |
| 정리 탭 | 비울 수 있는 스크린샷 · 비슷한 스크린샷 · 3달째 안 본 것 · 휴지통(갤러리 삭제까지), 꾹 눌러 크게 보기 |
| 분석 제외 | 서버로 보내지 않은 캡처(금융·민감 정보·Remine 화면)를 기기 안에서만 모아 보고 정리 |
| 예전 스크린샷 정리 | 범위(300장 · 1년 · 전부 · 직접)를 고르면 앱을 열 때마다 하루 300장씩 이어서 분석 |

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
  저장: 카테고리 · 태그 · 요약 · 메타데이터 (OCR 원문·이미지는 저장하지 않음)   ──▶ [DB]
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
| Infra | AWS EC2(서울, t4g.micro arm64) · Docker Compose · Caddy(HTTPS) · GitHub Actions · GHCR |

## 📊 Key Numbers

| 지표 | 결과 | 조건 |
|---|---|---|
| 첫 분석 시간 | **약 20분 → 4.6분** (1,197초 → 279초) | 갤럭시 실기기, 최근 300장 중 서버 분석 265장 |
| 첫 분석 시간 (운영) | **244장 약 3분 45초** (장당 0.92초) | AWS 운영 서버 재측정, 2026-11-19 |
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
- **ML Kit으로 재측정했습니다.** 앱의 실제 OCR로 같은 43장을 다시 돌리니 텍스트만 정확도가 44.2% → 67.4%로 올랐고, 하이브리드는 76.7%로 같으면서 이미지 전송은 33장 → 25장으로 줄었습니다.
- **개인정보 원칙은 테스트로 고정합니다.** 보낼 것은 앱의 한 곳(`sync_plan`)에서만 정하고, 실제 요청 본문 바이트를 검사해 민감 캡처·앱 이름·파일명이 나가지 않는지 확인합니다. 서버 로그에는 OCR 원문을 남기지 않습니다.
- **같은 캡처의 중복 분석을 막았습니다.** Gemini가 느려지자 앱 재전송과 서버 처리가 겹쳐 같은 캡처가 최대 5번 동시에 분석되고 500이 났습니다. (기기, 캡처) 단위 원자적 선점 + `IN_PROGRESS` 응답 + 요청 단위 마감(4분)으로 해결했고, 비동기 작업 전환은 규모에 비해 커서 미뤘습니다.
- **예전 스크린샷은 무료 한도 안에서 나눠 분석합니다.** 기기당 하루 300장, 서버 전체 하루 LLM 호출 예산의 70%까지만 쓰고(`SELECT … FOR UPDATE`로 원자적 차감, 실패·429는 환불), 첫 분석 300장도 이 한도에 포함합니다. 그래서 첫날 예전 정리는 남은 몫만 진행되고, 화면도 그렇게 안내합니다.
- **한계:** 정확도 표본이 43장(1인 라벨링)으로 작습니다.

더 많은 결정과 근거는 개발 중 남긴 의사결정 기록에 있습니다.

## 🚧 현재 상태

| 영역 | 상태 |
|---|---|
| 서버: 분류 · 관심사 집계 · FCM 푸시 · 예전 스크린샷 한도 | 운영 중 (AWS EC2, HTTPS, 자동 배포) |
| Flutter 앱 (Android) | 실기기 사용 중, APK 비공개 |
| CI | `server`(테스트 → 배포), `app`(analyze → 전체 테스트, PR마다) |

### API

| Method | Path | 설명 |
|---|---|---|
| POST | `/api/devices` | 기기 등록 |
| PUT · DELETE | `/api/devices/me/fcm-token` | 푸시 토큰 등록·삭제 |
| GET | `/api/config` | 분석 설정(이미지 기준값·크기 상한), 오늘 남은 예전 스크린샷 몫 |
| POST | `/api/screenshots/analyze` | OCR 텍스트(+ 이미지) 배치 분류, JSON 또는 multipart |
| GET | `/api/screenshots` | 분류된 스크린샷 목록 (카테고리·태그 필터, 페이지) |
| PATCH | `/api/screenshots/{id}/category` | 사용자 카테고리 수정 |
| POST | `/api/screenshots/trash` · `/restore` | 휴지통 넣기·되살리기 (관심사 집계·푸시에서 제외) |
| POST | `/api/screenshots/forget` | 서버 데이터 삭제 (갤러리에서 지운 캡처, 자기 캡처) |
| GET | `/api/categories/summary` | 홈 화면용 카테고리별 개수·대표 태그·최신 캡처 |
| GET | `/api/categories/accuracy` | 실사용 분류 정확도(수정률·검토 기준 정확도·혼동 쌍) |
| GET | `/api/interests` | 관심사 목록 (FORGOTTEN / RECENT, 장수, 연결 태그) |

요청·응답 형식과 오류 규칙은 [docs/spec.md](docs/spec.md)의 API 절을 참고하세요. `/api/dev/*`는 dev 프로필에서만 열립니다.

## ⚠️ 알려진 한계

- **자기 캡처 판정은 앱별입니다.** 갤럭시는 Remine 화면 캡처에 앱 이름을 붙이지 않아, 앱이 화면에 떠 있던 구간(시작 1초 전 ~ 끝 5초 뒤)으로 판정합니다. 걸러진 캡처는 서버로 가지 않고 "분석 제외"에 "Remine 화면"으로 모여 정리할 수 있습니다. 다만 같은 기기에 개발용 앱(Dev)과 실사용 앱을 함께 설치하면 서로의 캡처는 걸러지지 않습니다. 실사용자는 앱이 하나라 해당하지 않습니다.
- **잘못 걸린 자기 캡처를 되돌리는 기능은 없습니다.** 다른 앱 캡처가 "Remine 화면"으로 분류되면 지금은 휴지통으로 보내는 것만 됩니다. 앱 데이터를 삭제하면 규칙 도입 전 정리 기간이 길게 잡혀 이런 오판이 늘 수 있습니다.
- **APK는 공개하지 않습니다.** Gemini 무료 등급은 입력이 서비스 개선에 쓰일 수 있어, 공개 전 유료 등급 전환이나 초대 기기 제한이 필요합니다.
- **분석은 동기 요청입니다.** 외부 API가 크게 느려지면 요청 단위 마감(4분)에 걸려 다음 실행으로 넘어갑니다. 근본 해결은 비동기 분석 작업입니다.

## 📁 Structure

```
app/         Flutter 앱 (Android)
server/      Spring Boot 서버
deploy/      운영 서버 구성 (compose · Caddyfile · bootstrap · 백업)
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

```bash
# 3. 앱 (app/ 폴더에서, Android 기기 연결)
cd app
flutter test                                              # 비밀값 없이 도는 테스트
flutter run                                               # 가짜 데이터로 화면만
flutter run --dart-define=DATA=device --dart-define=API_BASE=http://<서버 주소>:8080   # 기기 사진 + 서버
```

디버그 빌드는 패키지명에 `.debug`가 붙은 별도 앱(re:mine Dev)으로 설치돼 실사용 앱 데이터를 덮어쓰지 않습니다.

배포 때 DB 접속 정보는 `SPRING_DATASOURCE_URL` · `SPRING_DATASOURCE_USERNAME` · `SPRING_DATASOURCE_PASSWORD`로 덮어씁니다.

## 🚀 Deploy

```
[GitHub Actions]  main push
  ./gradlew test → arm64 이미지 빌드 → GHCR push → SSH로 EC2에서 pull · 재시작 → https 헬스 체크

[EC2 t4g.micro, Docker Compose]
  Caddy (443, Let's Encrypt 자동) ──▶ server (prod 프로필) ──▶ postgres 17.6 (볼륨, 포트 비공개)
```

- **비밀값은 EC2에만 있습니다.** Gemini 키·DB 비밀번호·Firebase 키는 `/opt/remine/.env`·`secrets/`에만 두고, 레포·이미지·Actions 로그에는 없습니다. GitHub Secrets에는 SSH 접속 정보만 있습니다.
- **운영 프로필(prod)** 은 actuator `health`만 공개하고(상세 없음) `/api/dev/*`는 404입니다. Caddy도 `/api/*`와 `/actuator/health`만 서버로 넘깁니다.
- **1GB 인스턴스에 맞췄습니다.** JVM 힙은 컨테이너 한도(600MB)의 60%, Serial GC, 스왑 2GB. 이미지 빌드는 러너(x86)에서 Gradle을 네이티브로 돌리고 실행 단계만 arm64라 QEMU 에뮬레이션이 없습니다.
- **비용:** EC2 약 $7.6 + 퍼블릭 IPv4 약 $3.7 + EBS 20GB 약 $1.8 = 월 약 $13 (6개월 약 $79).
- **APK는 공개하지 않습니다.** 서버가 Gemini 무료 등급(입력이 학습에 쓰일 수 있음)이라, 공개 배포 전에 유료 등급 전환 또는 초대 기기 제한이 필요합니다. 지금은 시연 영상과 이 README로 대신합니다.
- **백업:** 매일 04:00 `pg_dump`(7일 보관, `deploy/backup.sh`).
- **이사:** 상태는 `compose.yaml` + `.env`·`secrets/` + DB 덤프뿐이라 Docker가 되는 다른 VM(Lightsail, Oracle ARM)으로 그대로 옮길 수 있습니다.

첫 준비는 `deploy/bootstrap.sh`(Docker·스왑·fail2ban·SSH 비밀번호 로그인 끄기·백업 cron)입니다.

## 📄 Docs

- [서비스 기획서](docs/spec.md)
- [LLM 분류 실험 요약](experiment/SUMMARY.md)