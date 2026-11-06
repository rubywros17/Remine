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

    test('모자라면 배지 여백 → 요소 간격 → 칸 안쪽 여백, 그래도 모자라면 배지만 숨긴다', () {
      // 기본 필요 폭: 10+8 + 점 8 + 아이콘 18 + 이름 60 + 배지 20+12 + 간격 18 = 154
      CategoryTileFit fit(double available) => fitCategoryTile(
        available: available,
        nameWidth: 60,
        badgeTextWidth: 20,
      );

      expect(fit(200), (
        padLeft: 10.0,
        padRight: 8.0,
        gap: 6.0,
        badgePad: 6.0,
        showBadge: true,
      ));
      final a = fit(150); // 4px 모자람 → 배지 여백만
      expect(
        (a.badgePad, a.gap, a.padLeft, a.showBadge),
        (4.0, 6.0, 10.0, true),
      );
      final b = fit(142); // 배지 여백 바닥(2) 뒤 간격
      expect((b.badgePad, b.gap, b.padLeft), (2.0, 6.0 - 4 / 3, 10.0));
      final c = fit(124); // 간격 바닥(2, 필요 134) 뒤 칸 안쪽 여백
      expect((c.badgePad, c.gap, c.showBadge), (2.0, 2.0, true));
      expect(c.padLeft, lessThan(10));
      // 배지까지 최소(2+2+8+18+60+20+4+6=120)보다 좁으면 배지를 숨기고 여백을 다시 맞춘다.
      final d = fit(119); // 배지 없이 기본 여백이면 116이라 충분
      expect(d.showBadge, isFalse);
      expect(d.padLeft, 10.0, reason: '배지가 빠져 여백은 기본값으로 충분');
      expect(d.gap, 6.0);
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

    Future<void> show(
      WidgetTester tester,
      RemineStore s, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
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

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('칸 크기·글자·아이콘은 수정 전 값 그대로 $size', (tester) async {
        final s = (await tester.runAsync(store))!;
        await show(tester, s, size: size);
        for (final c in Category.values) {
          final name = find.text(c.label);
          expect(
            tester.widget<Text>(name).style!.fontSize,
            15,
            reason: c.label,
          );
          expect(tester.widget<Text>(name).style!.fontWeight, FontWeight.w600);
          expect(
            tester.widget<Icon>(find.byIcon(categoryIcon(c))).size,
            18,
            reason: c.label,
          );
          final tile = find.ancestor(
            of: name,
            matching: find.byType(AnimatedContainer),
          );
          expect(tester.getSize(tile).height, 64, reason: c.label);
          final box =
              tester.widget<AnimatedContainer>(tile).decoration!
                  as BoxDecoration;
          expect(box.borderRadius, BorderRadius.circular(18));
          expect(
            (box.border! as Border).top.width,
            c == Category.shopping ? 2 : 1,
          );
        }
        expect(find.byType(FittedBox), findsNothing);
      });
    }

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
