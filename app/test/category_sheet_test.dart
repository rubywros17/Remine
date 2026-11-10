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
import 'package:remine/widgets/home_widgets.dart' show CategoryDot;

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
      // 기본 필요 폭: 18+16 + 점 8 + 아이콘 18 + 이름 60 + 배지 20+12 + 간격 18 = 170
      CategoryTileFit fit(double available) => fitCategoryTile(
        available: available,
        nameWidth: 60,
        badgeTextWidth: 20,
      );

      expect(fit(200), (
        padLeft: 18.0,
        padRight: 16.0,
        gap: 6.0,
        badgePad: 6.0,
        showBadge: true,
      ));
      final a = fit(166); // 4px 모자람 → 배지 여백만
      expect(
        (a.badgePad, a.gap, a.padLeft, a.showBadge),
        (4.0, 6.0, 18.0, true),
      );
      final b = fit(158); // 배지 여백 바닥(2, 필요 162) 뒤 간격
      expect((b.badgePad, b.gap, b.padLeft), (2.0, 6.0 - 4 / 3, 18.0));
      final c = fit(140); // 간격 바닥(2, 필요 150) 뒤 칸 안쪽 여백
      expect((c.badgePad, c.gap, c.showBadge), (2.0, 2.0, true));
      expect(c.padLeft, lessThan(18));
      expect(c.padRight, lessThan(16));
      // 배지까지 최소(2+2+8+18+60+20+4+6=120)보다 좁으면 배지를 숨긴다.
      expect(fit(119).showBadge, isFalse);
    });

    test('7칸 공통: 가장 빠듯한 칸 기준으로 모두 같은 여백, 안 들어가는 칸만 배지 숨김', () {
      Map<Category, CategoryTileFit> fits(double available) => fitCategoryTiles(
        available: available,
        widths: {
          for (final c in Category.values)
            c: c == Category.entertainment
                ? (name: 60.0, badge: 20.0) // 문화생활 + 세 자리
                : (name: 30.0, badge: 7.0),
        },
      );
      ({double l, double r, double g, double b}) pads(CategoryTileFit f) =>
          (l: f.padLeft, r: f.padRight, g: f.gap, b: f.badgePad);

      // 넉넉하면 기본값 그대로.
      expect(pads(fits(200)[Category.shopping]!), (
        l: 18.0,
        r: 16.0,
        g: 6.0,
        b: 6.0,
      ));
      // 문화생활만 빠듯해도 7칸 모두 같이 줄인다.
      final tight = fits(140);
      final first = pads(tight[Category.entertainment]!);
      expect(first.l, lessThan(18));
      for (final f in tight.values) {
        expect(pads(f), first);
        expect(f.showBadge, isTrue);
      }
      // 문화생활은 최소로도 안 들어가면 그 칸 배지만 숨기고, 여백은 공통(최소) 값.
      final narrow = fits(115);
      expect(narrow[Category.entertainment]!.showBadge, isFalse);
      expect(narrow[Category.shopping]!.showBadge, isTrue);
      expect(narrow.values.map(pads).toSet(), {
        (l: 2.0, r: 2.0, g: 2.0, b: 2.0),
      });
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
      Category auto = Category.shopping,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RemineScope(
          store: s,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: CategorySheet(
                  current: Category.shopping,
                  autoCategory: auto,
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

    testWidgets('부제는 카테고리 이름만 굵고, 조사는 보통 굵기', (tester) async {
      final s = (await tester.runAsync(store))!;
      for (final c in [
        Category.shopping,
        Category.place,
        Category.info,
        Category.entertainment,
        Category.etc,
      ]) {
        await show(tester, s, auto: c);
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().startsWith('AI는 '),
          ),
        );
        expect(rich.text.toPlainText(), 'AI는 ${withRo(c.label)} 분류했어요');
        final bold = <String>[];
        rich.text.visitChildren((span) {
          if (span is TextSpan &&
              span.text != null &&
              span.style?.fontWeight == FontWeight.w700) {
            bold.add(span.text!);
          }
          return true;
        });
        expect(bold, [c.label], reason: c.label);
      }
    });

    for (final size in const [Size(360, 800), Size(412, 915), Size(360, 640)]) {
      testWidgets('7칸 여백 동일, 색 점은 왼쪽부터, 배지 오른쪽 끝은 열마다 같은 줄 $size', (
        tester,
      ) async {
        await show(tester, (await tester.runAsync(store))!, size: size);
        Rect tileOf(Category c) => tester.getRect(
          find.ancestor(
            of: find.text(c.label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        Rect badgeOf(Category c) =>
            tester.getRect(find.byKey(ValueKey('count-badge-${c.code}')));

        final left = [
          Category.shopping,
          Category.place,
          Category.chat,
          Category.etc,
        ];
        final right = [
          Category.entertainment,
          Category.info,
          Category.schedule,
        ];
        final rights = <String>{}, lefts = <String>{};
        for (final column in [left, right]) {
          final edge = badgeOf(column.first).right;
          for (final c in column) {
            expect(badgeOf(c).right, closeTo(edge, 0.5), reason: c.label);
            // 7칸 모두 같은 여백: 칸 오른쪽~배지, 칸 왼쪽~색 점 거리가 모두 같다.
            rights.add((tileOf(c).right - badgeOf(c).right).toStringAsFixed(1));
            final dot = tester.getRect(
              find.descendant(
                of: find.ancestor(
                  of: find.text(c.label),
                  matching: find.byType(AnimatedContainer),
                ),
                matching: find.byType(CategoryDot),
              ),
            );
            lefts.add((dot.left - tileOf(c).left).toStringAsFixed(1));
          }
        }
        expect(rights, hasLength(1), reason: '칸마다 오른쪽 여백이 다르다: $rights');
        expect(lefts, hasLength(1), reason: '칸마다 왼쪽 여백이 다르다: $lefts');
      });
    }

    testWidgets('다른 칸을 고르면 원래 칸은 차콜 1.5px 점선, 원래 칸을 고르면 점선 없음', (tester) async {
      await show(tester, (await tester.runAsync(store))!);
      final dashed = find.byKey(const ValueKey('original-dashed-SHOPPING'));
      expect(dashed, findsNothing, reason: '처음에는 원래 칸이 선택돼 있다');

      await tester.tap(find.text('정보'));
      await tester.pumpAndSettle();
      expect(dashed, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(dashed).foregroundPainter!
              as DashedBorderPainter;
      expect(painter.color, AppColors.darkGray);
      expect(painter.width, 1.5);
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: dashed,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, AppColors.white, reason: '원래 칸은 선택이 아니다');
      expect((box.border! as Border).top.color, Colors.transparent);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('original-dashed'),
        ),
        findsOneWidget,
        reason: '점선은 원래 칸 하나뿐',
      );

      await tester.tap(find.text('쇼핑'));
      await tester.pumpAndSettle();
      expect(dashed, findsNothing);
      expect(tileBox(tester, '쇼핑').color, AppColors.darkGray);
    });
  });
}
