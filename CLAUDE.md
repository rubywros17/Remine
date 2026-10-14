# CLAUDE.md

**Remine** (리마인) — 스크린샷 자동 정리 + 잊은 관심사 알림 앱.
기능·범위·API·DB 상세는 **`docs/spec.md`**를 참고한다. 기능을 추가하거나 바꾸기 전에 spec의 MVP 범위를 먼저 확인할 것.

## 프로젝트 성격
- 1인 개발, **백엔드 포트폴리오**가 주목적이다. 서버 코드는 설계 의도가 드러나게 작성한다.
- 개발자는 Java/Spring Boot에 익숙하고, Flutter/Dart는 처음이다. 앱 코드에서 낯선 Dart 문법이나 Flutter 개념을 쓸 때는 짧게 설명을 덧붙인다.

## 구조
```
app/      Flutter 앱 (안드로이드 우선)
server/   Spring Boot 서버
docs/     기획·설계 문서
```

## 스택
- 앱: Flutter (Dart), photo_manager, google_mlkit_text_recognition, firebase_messaging
- 서버: Spring Boot 4.1.1 / Java 21 / H2(임시)
- DB(운영) / LLM: 미정 → 정해지면 이 파일 갱신

## 핵심 원칙
- **원본 이미지는 서버로 보내지 않는다.** 앱에서 OCR 후 텍스트와 메타데이터만 전송한다.
- MVP 범위 밖 기능(다운로드 폴더, 인스타 연동, 로그인, iOS 대응 등)은 먼저 제안만 하고 바로 구현하지 않는다.
- API 키, FCM 서버 키 등 비밀값은 코드에 넣지 않고 환경변수 / `.env`로 관리한다. `.env`는 커밋하지 않는다.

## 개발 환경
- Windows (LG 그램) + VS Code
- 테스트: 갤럭시 실기기 (USB 디버깅). 에뮬레이터는 기본으로 쓰지 않는다.
- 명령어는 Windows(PowerShell) 기준으로 안내한다.

## 자주 쓰는 명령
```
# 앱
cd app
flutter pub get
flutter run            # 연결된 갤럭시에서 실행
flutter analyze

# 서버
cd server
./gradlew bootRun
./gradlew test
```

## 코드 규칙
- 서버: 계층 구조 (controller / service / repository / domain / dto). 엔티티를 API 응답으로 직접 노출하지 않는다.
- 서버: 새 기능에는 서비스 계층 단위 테스트를 함께 작성한다.
- 앱: 화면(screens) / 위젯(widgets) / 서비스(services) / 모델(models) 폴더로 나눈다.
- 커밋 메시지: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:` 접두어 사용.


## 작업 방식
- 필요한 파일·섹션만 읽고, spec.md 전체는 범위 확인이 필요할 때만 읽는다.
- 작업 완료 보고는 변경 파일 목록 + 핵심 결정 이유 3줄 이내.
- 큰 기능은 구현 전에 만들 파일·구조를 먼저 보여주고 확인받는다.
- 완료 조건: ./gradlew test 통과.
- Git: 기능 단위 브랜치(feat/...), 작업 단위로 커밋 나누기.