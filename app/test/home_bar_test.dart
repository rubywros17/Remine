import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/category_summary.dart';
import 'package:remine/widgets/home_widgets.dart';

import 'support/fake_device.dart';

/// [counts] 순서가 곧 "서버 순서". 정렬이 이 순서에 기대지 않는지 보려고 일부러 섞어 넘긴다.
CategorySummary _summary(Map<Category, int> counts) => CategorySummary(
  categories: [
    for (final e in counts.entries)
      CategorySummaryItem(
        category: e.key,
        count: e.value,
        topTags: const [],
        recentAssetIds: const [],
      ),
  ],
);

List<Category> _order(CategorySummary s) =>
    s.sortedForHome.map((i) => i.category).toList();

Future<void> _pumpBar(
  WidgetTester tester,
  CategorySummary s, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: CategoryRatioBar(items: s.sortedForHome),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('분석 제외 알약', excludedPillTests);

  group('sortedForHome', () {
    test('동점이면 카테고리 고정 순서다(서버 순서와 상관없이)', () {
      final s = _summary({
        Category.schedule: 0,
        Category.place: 3,
        Category.etc: 0,
        Category.chat: 0,
        Category.shopping: 3,
        Category.info: 0,
        Category.entertainment: 5,
      });
      expect(_order(s), [
        Category.entertainment,
        Category.shopping,
        Category.place,
        Category.info,
        Category.chat,
        Category.schedule,
        Category.etc,
      ]);
    });

    test('기타는 개수가 가장 많아도 맨 끝이다', () {
      final s = _summary({
        Category.etc: 99,
        Category.chat: 1,
        Category.shopping: 2,
        for (final c in [
          Category.entertainment,
          Category.place,
          Category.info,
          Category.schedule,
        ])
          c: 0,
      });
      final order = _order(s);
      expect(order.take(2), [Category.shopping, Category.chat]);
      expect(order.last, Category.etc);
    });
  });

  group('ratioBarWidths', () {
    test('1장도 최소 폭을 받고, 칸 폭 + 간격 합이 막대 폭과 같다', () {
      final w = ratioBarWidths([1000, 1], 300);
      expect(w[1], closeTo(AppCategoryColors.barMinSegment, 0.5));
      expect(w[0], greaterThan(w[1]));
      expect(
        w.reduce((a, b) => a + b) + AppCategoryColors.barGap,
        closeTo(300, 1e-9),
      );
    });

    test('최소 폭 합보다 좁으면 똑같이 나누고 음수가 없다', () {
      final w = ratioBarWidths([5, 1, 1], 20);
      expect(w.toSet().length, 1);
      expect(
        w.reduce((a, b) => a + b) + 2 * AppCategoryColors.barGap,
        closeTo(20, 1e-9),
      );
      expect(ratioBarWidths([1, 1], 1), everyElement(0));
    });
  });

  group('CategoryRatioBar', () {
    final s = _summary({
      Category.shopping: 6,
      Category.entertainment: 4,
      Category.place: 0,
      Category.info: 2,
      Category.chat: 0,
      Category.schedule: 0,
      Category.etc: 1,
    });

    testWidgets('0장 카테고리는 칸이 없고, 라벨은 칸 순서대로 "N장"을 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBar(tester, s);
      await tester.pumpAndSettle();

      expect(find.byType(ColoredBox), findsNWidgets(4));
      expect(
        find.bySemanticsLabel('쇼핑 6장, 문화생활 4장, 정보 2장, 기타 1장'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('애니메이션이 끝나면 칸마다 실제로 너비·높이 > 0으로 그려진다', (tester) async {
      await _pumpBar(tester, s);
      await tester.pumpAndSettle();

      final cells = find.byType(ColoredBox);
      expect(cells, findsNWidgets(4));
      var sum = 0.0;
      for (final e in cells.evaluate()) {
        final size = (e.renderObject! as RenderBox).size;
        expect(size.width, greaterThan(0));
        expect(size.height, AppCategoryColors.barHeight);
        sum += size.width;
      }
      expect(sum + 3 * AppCategoryColors.barGap, closeTo(300, 1e-6));
    });

    testWidgets('처음엔 왼쪽부터 채워지고, 모션 줄이기면 바로 다 보인다', (tester) async {
      double barWidth() => tester.getSize(find.byType(ClipRect).first).width;

      await _pumpBar(tester, s);
      await tester.pump(const Duration(milliseconds: 60));
      expect(barWidth(), lessThan(300));
      await tester.pumpAndSettle();
      expect(barWidth(), 300);

      await tester.pumpWidget(const SizedBox()); // 새로 그리게 비운다
      await _pumpBar(tester, s, reduceMotion: true);
      await tester.pump();
      expect(barWidth(), 300);
    });

    testWidgets('전부 0장이면 막대를 그리지 않는다', (tester) async {
      await _pumpBar(tester, _summary({for (final c in Category.values) c: 0}));
      expect(find.byType(ColoredBox), findsNothing);
    });
  });

  testWidgets('홈의 막대 합계는 알약 개수 합계와 같다(가짜 데이터)', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 10, 19, 12);
    final repo = FakeScreenshotRepository(now: () => now);
    await tester.pumpWidget(RemineApp(repository: repo, now: () => now));
    await tester.pumpAndSettle();

    final summary = await repo.summary();
    final shown = summary.sortedForHome.where((i) => i.count > 0);
    final label = shown
        .map((i) => '${i.category.label} ${i.count}장')
        .join(', ');
    expect(find.bySemanticsLabel(label), findsOneWidget);
    final pillSum = tester
        .widgetList<CategoryPill>(find.byType(CategoryPill))
        .fold(0, (sum, p) => sum + p.item.count);
    expect(shown.fold(0, (sum, i) => sum + i.count), pillSum);
    expect(pillSum, summary.total);
    handle.dispose();
  });
}

void excludedPillTests() {
  final now = DateTime(2026, 10, 19, 12);

  Future<void> pumpDevice(WidgetTester tester, {required int hidden}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final services = fakeServices(FakeGalleryReader());
    for (var i = 0; i < hidden; i++) {
      await services.capture.verdicts.save(
        StoredVerdict.of(
          const LocalVerdict(
            route: LocalRoute.deviceOnly,
            category: Category.etc,
            hidden: true,
            reasons: ['CARD'],
          ),
          assetId: 'h$i',
          takenAt: now,
          modifiedAt: 1,
          now: now,
        ),
      );
    }
    await tester.pumpWidget(
      RemineApp(
        repository: FakeScreenshotRepository(now: () => now),
        now: () => now,
        device: services,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('분석 제외 알약은 기타 바로 뒤이고, 막대 라벨에는 없다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDevice(tester, hidden: 2);

    final wrap = tester.widget<Wrap>(
      find.ancestor(of: find.byType(ExcludedPill), matching: find.byType(Wrap)),
    );
    final last2 = wrap.children.sublist(wrap.children.length - 2);
    expect((last2[0] as CategoryPill).item.category, Category.etc);
    expect(last2[1], isA<ExcludedPill>());
    expect((last2[1] as ExcludedPill).count, 2);
    expect(
      find.descendant(
        of: find.byType(ExcludedPill),
        matching: find.byType(CategoryDot),
      ),
      findsNothing,
    );
    final barLabel = tester.getSemantics(find.byType(CategoryRatioBar)).label;
    expect(barLabel, isNot(contains('분석 제외')));
    handle.dispose();
  });

  testWidgets('분석 제외가 0장이면 알약을 숨긴다', (tester) async {
    await pumpDevice(tester, hidden: 0);
    expect(find.byType(ExcludedPill), findsNothing);
  });
}
