import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/settings_screen.dart';
import 'package:remine/screens/trash_screen.dart';
import 'package:remine/widgets/small_widgets.dart';

import 'support/fake_device.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

TrashedShot _shot(String id) => TrashedShot(
  assetId: id,
  category: Category.shopping,
  takenAt: _now,
  trashedAt: _now,
  onServer: false,
);

Future<void> _pumpApp(WidgetTester tester, InMemoryTrashStore store) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now),
      now: () => _now,
      device: fakeServices(FakeGalleryReader(), trash: store),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inTrashTile(String text) => find.descendant(
  of: find.byKey(const ValueKey('tidy-trash')),
  matching: find.text(text),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.runAsync(pumpEventQueue);
  await tester.pumpAndSettle();
}

void main() {
  late InMemoryTrashStore store;

  setUp(() async {
    store = InMemoryTrashStore();
    await store.add(_shot('a'));
    await store.add(_shot('b'));
  });

  testWidgets('정리 탭: 휴지통 장수를 보여 주고, 누르면 휴지통 화면이 열린다', (tester) async {
    await _pumpApp(tester, store);
    await _tap(tester, find.text('정리'));

    expect(find.text('지워도 될 만한 스크린샷을 모아 드릴게요'), findsOneWidget);
    expect(find.text('휴지통'), findsOneWidget);
    expect(_inTrashTile('2장'), findsOneWidget);
    expect(
      find.bySemanticsLabel('이번 주 비운 스크린샷 2장'),
      findsOneWidget,
      reason: '휴지통에 넣은 날짜로 센다',
    );

    await _tap(tester, find.text('휴지통'));
    expect(find.byType(TrashScreen), findsOneWidget);
    expect(find.text('휴지통 2장'), findsOneWidget);
  });

  testWidgets('휴지통에서 되살리고 돌아오면 장수가 바뀐다', (tester) async {
    await _pumpApp(tester, store);
    await _tap(tester, find.text('정리'));
    await _tap(tester, find.text('휴지통'));

    await store.restore('a');
    await _tap(tester, find.byType(BackButtonCircle).first);
    expect(find.byType(TrashScreen), findsNothing);
    expect(_inTrashTile('1장'), findsOneWidget);
    expect(
      find.bySemanticsLabel('이번 주 비운 스크린샷 1장'),
      findsOneWidget,
      reason: '되살린 장은 비운 기록에서도 빠진다',
    );
  });

  testWidgets('설정은 홈 오른쪽 위 톱니에서 열리고, 설정 > 휴지통도 그대로 있다', (tester) async {
    await _pumpApp(tester, store);
    await _tap(tester, find.byIcon(LucideIcons.settings));

    expect(find.byType(SettingsScreen), findsOneWidget);
    await _tap(tester, find.text('휴지통'));
    expect(find.byType(TrashScreen), findsOneWidget);
  });
}
