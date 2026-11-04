import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/screens/detail_screen.dart' show swipeTutorialText;

import 'support/fake_device.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

/// 상세 첫 진입 "위로 밀어 삭제" 안내. 설정(기기 모드)에 한 번 본 것을 기록한다.
void main() {
  Future<void> pumpApp(WidgetTester tester, SettingsStore settings) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DeviceScope(
        services: fakeServices(FakeGalleryReader(), settings: settings),
        child: RemineApp(
          repository: FakeScreenshotRepository(now: () => _now),
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.text('쇼핑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Hero).first);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('처음 들어오면 보이고, [알겠어요]로 닫으면 다시 들어와도 안 보인다', (tester) async {
    final settings = InMemorySettingsStore(false);
    await pumpApp(tester, settings);

    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsOneWidget);

    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();
    expect(find.text(swipeTutorialText), findsNothing);
    expect(await settings.swipeTutorialSeen(), isTrue);

    await back(tester);
    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsNothing);
  });

  testWidgets('덮개 위에서도 카드를 끌 수 있고, 끌기 시작하면 닫히며 기록된다', (tester) async {
    final settings = InMemorySettingsStore(false);
    await pumpApp(tester, settings);
    await openDetail(tester);

    final card = find.descendant(
      of: find.byType(PageView),
      matching: find.byType(Hero),
    );
    final g = await tester.startGesture(tester.getCenter(card));
    await g.moveBy(const Offset(0, -(kTouchSlop + 2)));
    await g.moveBy(const Offset(0, -40));
    await tester.pump();

    expect(find.text(swipeTutorialText), findsNothing);
    expect(await settings.swipeTutorialSeen(), isTrue);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('이미 봤으면 보이지 않는다', (tester) async {
    final settings = InMemorySettingsStore(false);
    await settings.setSwipeTutorialSeen();
    await pumpApp(tester, settings);

    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsNothing);
  });

  testWidgets('애니메이션 줄이기여도 바로 보인다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, InMemorySettingsStore(false));

    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsOneWidget);
  });

  testWidgets('가짜 데이터 모드도 처음 한 번 보이고, 앱마다 따로 기억한다(테스트끼리 섞이지 않음)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Future<void> pumpFake() async {
      await tester.pumpWidget(
        RemineApp(
          key: UniqueKey(), // 새 앱(새 스토어)
          repository: FakeScreenshotRepository(now: () => _now),
          now: () => _now,
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpFake();
    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsOneWidget);
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();
    await back(tester);
    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsNothing, reason: '같은 실행에서는 다시 안 뜬다');

    await pumpFake();
    await openDetail(tester);
    expect(find.text(swipeTutorialText), findsOneWidget, reason: '새 앱은 처음부터');
  });
}
