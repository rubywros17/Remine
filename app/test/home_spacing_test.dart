import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

final _now = DateTime(2026, 10, 19, 12);

/// 홈 세로 간격: 상단바-제목, 제목-카드, 카드-서랍 제목, 막대-알약, 첫 화면 알약-탭바, 끝까지 스크롤한 뒤 알약-탭바.
Future<List<double>> homeGaps(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now),
      now: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  Rect r(Finder f) => tester.getRect(f);
  Rect pills() => r(find.byType(Wrap).last);
  final tab = r(find.byType(AppTabBar));
  final gaps = [
    r(find.byType(HighlighterText)).top - r(find.byType(BrandHeader)).bottom,
    r(find.byType(InterestCard)).top - r(find.byType(HighlighterText)).bottom,
    r(find.text('내 캡처 서랍')).top - r(find.byType(InterestCard)).bottom,
    pills().top - r(find.byType(CategoryRatioBar)).bottom,
    tab.top - pills().bottom,
  ];
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -2000),
  );
  await tester.pumpAndSettle();
  return [...gaps, tab.top - pills().bottom];
}

/// 카드-서랍 제목 박스 간격의 기본값(보이는 글자 끝 보정 포함, 글자 크기 1배).
final double _cardToDrawer =
    AppSpacing.s24 +
    AppText.display.fontSize! * AppHome.titleInkBottom -
    AppText.sectionTitle.fontSize! * AppHome.drawerTitleInkTop;

void main() {
  testWidgets(
    '화면이 남으면 제목-카드·카드-서랍 제목이 남는 높이의 1/3씩(각각 최대 +32) 똑같이 늘고, 나머지는 알약 아래로',
    (tester) async {
      final g = await homeGaps(tester, const Size(412, 915));
      expect(g[0], closeTo(AppSpacing.s24, 0.01));
      expect(g[3], closeTo(AppSpacing.s16, 0.01));
      final extra = g[1] - AppSpacing.s24;
      expect(
        g[2] - _cardToDrawer,
        closeTo(extra, 0.01),
        reason: '두 간격이 똑같이 는다',
      );
      final leftover = 2 * extra + g[5] - AppHome.pillsToTabMin;
      expect(extra, greaterThan(0));
      expect(
        extra,
        closeTo(
          math.min(leftover * AppHome.cardGapShare, AppHome.cardGapMaxExtra),
          0.01,
        ),
      );
      expect(g[5], g[4], reason: '스크롤되지 않는다');
    },
  );

  for (final size in const [Size(360, 800), Size(360, 640)]) {
    testWidgets('모자라면 간격은 기본값, 끝까지 스크롤하면 알약 아래 최소 여백 $size', (tester) async {
      final g = await homeGaps(tester, size);
      expect(g[0], closeTo(AppSpacing.s24, 0.01));
      expect(g[1], closeTo(AppSpacing.s24, 0.01));
      expect(g[2], closeTo(_cardToDrawer, 0.01));
      expect(g[3], closeTo(AppSpacing.s16, 0.01));
      expect(g[5], closeTo(AppHome.pillsToTabMin, 0.01));
    });
  }
}
