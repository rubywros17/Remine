import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/screens/consent_screen.dart' show consentTitle;
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/widgets/wordmark.dart';

import 'support/fake_device.dart';

/// 디버그 화면의 테스트용 초기화 버튼. 진입(홈 워드마크 길게 누르기)이 kDebugMode로 막혀 릴리스에는 없다.
void main() {
  Future<void> openDebug(WidgetTester tester, SettingsStore settings) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RemineApp(device: fakeServices(FakeGalleryReader(), settings: settings)),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(Wordmark).first);
    await tester.pumpAndSettle();
    expect(find.byType(DebugOcrScreen), findsOneWidget);
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  testWidgets('[튜토리얼 다시 보기]는 봤음 기록만 지운다', (tester) async {
    final settings = InMemorySettingsStore(true);
    await settings.setSwipeTutorialSeen();
    await openDebug(tester, settings);

    await tapChip(tester, '튜토리얼 다시 보기');

    expect(await settings.swipeTutorialSeen(), isFalse);
    expect(await settings.imageConsent(), isTrue);
    expect(find.byType(DebugOcrScreen), findsOneWidget, reason: '화면은 그대로');
  });

  testWidgets('[첫 실행 안내 다시 보기]는 선택만 지우고 첫 실행 게이트로 돌아간다', (tester) async {
    final settings = InMemorySettingsStore(true);
    await settings.setNotificationsEnabled(false);
    await settings.setSwipeTutorialSeen();
    await openDebug(tester, settings);

    await tapChip(tester, '첫 실행 안내 다시 보기');

    expect(find.byType(DebugOcrScreen), findsNothing);
    expect(find.text(consentTitle), findsOneWidget, reason: '이미지 동의부터 다시 묻는다');
    expect(await settings.imageConsent(), isNull);
    expect(await settings.notificationsEnabled(), isNull);
    expect(await settings.swipeTutorialSeen(), isTrue, reason: '튜토리얼 기록은 따로');

    await tester.tap(find.text('동의할래요'));
    await tester.pumpAndSettle();
    expect(find.text(consentTitle), findsNothing);
    expect(await settings.imageConsent(), isTrue);
  });
}
