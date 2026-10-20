# remine (앱)

Flutter 앱 (Android + web). 디자인 기준은 [../docs/design.md](../docs/design.md).

2주차: 가짜 데이터(Fake 저장소)로 화면만 만든 상태다. 서버 연동은 3주차에 `ScreenshotRepository` 구현만 바꿔 끼운다.

```bash
cd app
flutter pub get
flutter run -d chrome                                    # 크롬
flutter devices                                          # 폰 id 확인 (USB 디버깅)
flutter run -d <id>                                      # 연결된 갤럭시
flutter run -d chrome --dart-define=START_SCREEN=analysis  # 첫 분석 화면(정적)에서 시작
flutter analyze
flutter test
```

### 구조 (`lib/`)
```
core/      tokens.dart(색·폰트·모서리·간격·모션), helpers.dart(아이콘·날짜 표기·화면 전환)
models/    서버 응답과 같은 이름·타입 (spec 9장)
data/      ScreenshotRepository(인터페이스) · FakeScreenshotRepository · RemineStore(상태)
screens/   shell(탭) · home · category · detail · analysis
widgets/   공용 위젯 (칩·알약·시트·탭바 등)
```

### 안드로이드 빌드 준비
Gradle이 NDK 28.2.13676358을 자동 설치하지 못하면(`Android sdkmanager did not install NDK`) 한 번 직접 설치한다.
**Android Studio → SDK Manager → SDK Tools → "NDK (Side by side)" → 28.2.13676358 선택 → Apply.**
(이 PC의 `sdkmanager`는 deprecated 안내만 나오는 새 도구라 Gradle의 자동 설치가 실패한다. 설치 후 `flutter build apk --debug`로 확인.)
