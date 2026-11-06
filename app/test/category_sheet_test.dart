import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/core/helpers.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/widgets/category_sheet.dart';

void main() {
  group('조사', () {
    test('받침이 있으면 "으로", 없거나 ㄹ받침이면 "로"', () {
      expect(withRo('쇼핑'), '쇼핑으로');
      expect(withRo('장소'), '장소로');
      expect(withRo('정보'), '정보로');
      expect(withRo('문화생활'), '문화생활로');
      expect(withRo('기타'), '기타로');
      expect(withRo('일정'), '일정으로');
    });

    test('이에요/예요', () {
      expect(copulaFor('쇼핑'), '이에요');
      expect(copulaFor('정보'), '예요');
      expect(copulaFor('문화생활'), '이에요');
    });
  });

  group('장수 배지', () {
    test('999를 넘으면 999+, 0장이어도 0', () {
      expect(countBadgeText(0), '0');
      expect(countBadgeText(999), '999');
      expect(countBadgeText(1000), '999+');
    });

    test('모자라면 배지 여백 → 요소 간격 → 칸 안쪽 여백 순서로 줄인다', () {
      // 기본 필요 폭: 10+8 + 8+20 + 이름 60 + 배지 20+12 + 간격 18 = 156
      CategoryTileFit fit(double available) => fitCategoryTile(
        available: available,
        nameWidth: 60,
        badgeTextWidth: 20,
      );

      expect(fit(200), (padLeft: 10.0, padRight: 8.0, gap: 6.0, badgePad: 6.0));
      final a = fit(152); // 4px 모자람 → 배지 여백만
      expect((a.badgePad, a.gap, a.padLeft), (4.0, 6.0, 10.0));
      final b = fit(144); // 배지 여백 바닥(2) 뒤 간격
      expect((b.badgePad, b.gap, b.padLeft), (2.0, 6.0 - 4 / 3, 10.0));
      final c = fit(120); // 간격 바닥(2) 뒤 칸 안쪽 여백
      expect((c.badgePad, c.gap), (2.0, 2.0));
      expect(c.padLeft, lessThan(10));
      expect(c.padRight, lessThan(8));
    });
  });

  group('시트', () {
    final now = DateTime(2026, 11, 6, 12);

    /// 쇼핑 3장(그중 1장 휴지통) · 정보 2장.
    Future<RemineStore> store() async {
      ScreenshotItem shot(int id, Category c) => ScreenshotItem(
        id: id,
        localAssetId: 's$id',
        takenAt: now.subtract(Duration(hours: id)),
        category: c,
        tags: const [],
      );
      final s = RemineStore(
        FakeScreenshotRepository(
          now: () => now,
          seed: [
            shot(1, Category.shopping),
            shot(2, Category.shopping),
            shot(3, Category.shopping),
            shot(4, Category.info),
            shot(5, Category.info),
          ],
        ),
        now: () => now,
      );
      await s.trash(1);
      return s;
    }

    Future<void> show(WidgetTester tester, RemineStore s) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RemineScope(
          store: s,
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: CategorySheet(
                  current: Category.shopping,
                  autoCategory: Category.shopping,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String badge(WidgetTester tester, Category c) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('count-badge-${c.code}')),
            matching: find.byType(Text),
          ),
        )
        .data!;

    BoxDecoration tileBox(WidgetTester tester, String label) =>
        tester
                .widget<AnimatedContainer>(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;

    testWidgets('배지 숫자는 홈 요약 값(휴지통 제외), 0장도 0', (tester) async {
      final s = (await tester.runAsync(store))!;
      await show(tester, s);
      final home = (await tester.runAsync(s.repository.summary))!;
      for (final c in Category.values) {
        expect(badge(tester, c), '${home.of(c).count}', reason: c.label);
      }
      expect(badge(tester, Category.shopping), '2');
      expect(badge(tester, Category.place), '0');
    });

    testWidgets('선택 칸은 차콜 바탕·테두리, 체크 표시 없음', (tester) async {
      await show(tester, (await tester.runAsync(store))!);
      final on = tileBox(tester, '쇼핑');
      expect(on.color, AppColors.darkGray);
      expect((on.border! as Border).top.color, AppColors.darkGray);
      expect(tileBox(tester, '정보').color, AppColors.white);
      expect(find.byIcon(LucideIcons.check), findsNothing);

      final name = tester.widget<Text>(find.text('쇼핑'));
      expect(name.style!.color, AppColors.white);
      expect(name.maxLines, 1);
    });

    testWidgets('버튼: 같은 서랍이면 "그대로 둘게요", 다르면 조사를 맞춰 "옮길게요"', (tester) async {
      await show(tester, (await tester.runAsync(store))!);
      expect(find.text('어느 서랍에 넣을까요?'), findsOneWidget);
      expect(find.text('쇼핑 그대로 둘게요'), findsOneWidget);

      for (final (label, button) in [
        ('정보', '정보로 옮길게요'),
        ('일정', '일정으로 옮길게요'),
        ('문화생활', '문화생활로 옮길게요'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(button), findsOneWidget);
        expect(tileBox(tester, label).color, AppColors.darkGray);
      }
    });
  });
}
