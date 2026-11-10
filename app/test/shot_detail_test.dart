import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/helpers.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

final _now = DateTime(2026, 11, 10, 12);

Future<void> _openDetail(WidgetTester tester, {String? sourceApp}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final shot = ScreenshotItem(
    id: 1,
    localAssetId: 'a',
    takenAt: DateTime(2026, 11, 6, 13, 58),
    category: Category.shopping,
    summary: '가디건 재입고',
    tags: const ['가디건', '재입고'],
    sourceApp: sourceApp,
  );
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now, seed: [shot]),
      now: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('쇼핑').first);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Hero).first);
  await tester.pumpAndSettle();
}

void main() {
  test('촬영 시각은 "연.월.일 (요일)  |  시:분" 24시간제', () {
    expect(
      formatStamp(DateTime(2026, 11, 6, 13, 58)),
      '2026.11.06 (FRI)  |  13:58',
    );
    expect(
      formatStamp(DateTime(2026, 1, 5, 9, 3)),
      '2026.01.05 (MON)  |  09:03',
    );
  });

  testWidgets('앱 이름이 있으면 차콜 출처 칩(흰 대문자) + 날짜', (tester) async {
    await _openDetail(tester, sourceApp: 'Instagram');

    final chip = find.byKey(const ValueKey('source-chip'));
    expect(chip, findsOneWidget);
    expect(
      (tester.widget<DecoratedBox>(chip).decoration as BoxDecoration).color,
      AppColors.darkGray,
    );
    final label = tester.widget<Text>(
      find.descendant(of: chip, matching: find.byType(Text)),
    );
    expect(label.data, 'INSTAGRAM');
    expect(label.style?.color, AppColors.white);
    expect(find.text('2026.11.06 (FRI)  |  13:58'), findsOneWidget);
  });

  testWidgets('앱 이름이 없으면 출처 칩 없이 날짜만', (tester) async {
    await _openDetail(tester);

    expect(find.byKey(const ValueKey('source-chip')), findsNothing);
    expect(find.text('2026.11.06 (FRI)  |  13:58'), findsOneWidget);
  });

  testWidgets('카테고리 버튼은 흰 알약·연회색 테두리(색 점·이름·연필), 누르면 시트가 열린다', (tester) async {
    await _openDetail(tester);

    final button = find.byKey(const ValueKey('category-chip-1'));
    final pill = tester.widget<AppChip>(
      find.descendant(of: button, matching: find.byType(AppChip)),
    );
    expect(pill.background, AppColors.white);
    expect(pill.borderColor, AppColors.border);
    expect(
      find.descendant(of: button, matching: find.byType(CategoryDot)),
      findsOneWidget,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('어느 서랍에 넣을까요?'), findsOneWidget);
  });
}
