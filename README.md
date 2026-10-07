# 📸 Remine

> 잊은 캡처, 다시 꺼내드릴게요

나중에 보려고 찍어두고 잊어버린 스크린샷을 자동으로 분류해 보여주고,
자주 캡처했던 **잊은 관심사**를 먼저 꺼내서 알려주는 앱입니다.

**Remine** = **re** (다시) + **mine** (캐내다 / 내 것) — 묵혀둔 캡처를 다시 캐내서, 다시 내 것으로.

---

## ✨ MVP 기능

| 기능 | 설명 |
|---|---|
| 스크린샷 불러오기 | 갤럭시 앨범의 Screenshots 폴더를 자동으로 수집 |
| 기기 내 OCR | ML Kit 한국어 인식. **원본 이미지는 서버로 보내지 않음** |
| AI 분류 | LLM으로 카테고리 · 태그 · 한 줄 요약 생성 |
| 정리 화면 | 카테고리 카드 · 이미지 그리드 · 태그 필터 |
| 잊은 관심사 알림 | 태그 빈도를 집계해 반복된 관심사를 주 1회 푸시로 알림 |

## 🏗️ 아키텍처

```
[Flutter 앱] ── OCR 텍스트 + 메타데이터 ──▶ [Spring Boot 서버] ──▶ [LLM]
     ▲                                          │
     │                                          ▼
     └──────────── FCM 푸시 ◀── 관심사 집계 ── [DB]
```

## 🛠️ Tech Stack

| 영역 | 기술 |
|---|---|
| App | Flutter (Dart), photo_manager, Google ML Kit |
| Backend | Spring Boot (Java) |
| Push | Firebase Cloud Messaging |
| DB | TBD |
| AI | LLM (TBD) |

## 📁 Structure

```
app/      Flutter 앱 (Android 우선)
server/   Spring Boot 서버
docs/     기획 · 설계 문서
```

## 📄 Docs

- [서비스 기획서](docs/spec.md)

---

🚧 현재 MVP 개발 중입니다.
