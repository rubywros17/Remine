import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/widgets/small_widgets.dart';

import 'support/fake_device.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

Future<void> _openDetail(
  WidgetTester tester, {
  FakeGalleryReader? reader,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now),
      now: () => _now,
      device: reader == null ? null : fakeServices(reader),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('쇼핑'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Hero).first);
  await tester.pumpAndSettle();
}

Finder get _card =>
    find.descendant(of: find.byType(PageView), matching: find.byType(Hero));

Finder get _blur => find.byWidgetPredicate(
  (w) => w is ImageFiltered, // 배경의 흐린 사진
);

void main() {
  group('배경', () {
    testWidgets('차콜 단색이다(블러 사진 배경 없음), 기기 모드에서도 같다', (tester) async {
      await _openDetail(tester, reader: FakeGalleryReader());

      expect(_blur, findsNothing);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        AppColors.darkGray,
      );
    });

    testWidgets('상세에서는 배경용 썸네일을 따로 읽지 않는다(카드 사진 1장만)', (tester) async {
      final reader = FakeGalleryReader();
      await _openDetail(tester, reader: reader);

      final detailRequests = reader.thumbnailRequests
          .where((r) => r.$1 == 200)
          .toList();
      expect(detailRequests, isEmpty, reason: '배경용(200px) 썸네일 요청이 남아 있다');
    });
  });

  group('이미지 카드', () {
    testWidgets('최대 폭 78%, 상단 바 아래 최소 16px 여백', (tester) async {
      await _openDetail(tester);

      final card = tester.getRect(_card);
      expect(card.width, lessThanOrEqualTo(390 * 0.78 + 0.5));
      expect(card.top - 56, greaterThanOrEqualTo(16 - 0.5));
    });

    testWidgets('가만히 있을 때 기울기는 -2°다', (tester) async {
      await _openDetail(tester);

      final angles = tester
          .widgetList<Transform>(
            find.descendant(of: _card, matching: find.byType(Transform)),
          )
          .map((t) {
            final m = t.transform.storage;
            return math.atan2(m[1], m[0]);
          })
          .toList();
      expect(
        angles.any((a) => (a - (-2 * math.pi / 180)).abs() < 0.001),
        isTrue,
        reason: '카드 기울기 $angles',
      );
    });

    testWidgets('드래그 중에는 기존처럼 더 기울어진다', (tester) async {
      await _openDetail(tester);

      double angleOf() => tester
          .widgetList<Transform>(
            find.ancestor(of: _card, matching: find.byType(Transform)),
          )
          .map(
            (t) => math.atan2(t.transform.storage[1], t.transform.storage[0]),
          )
          .fold<double>(0, (sum, a) => sum + a);
      final idle = angleOf();
      final g = await tester.startGesture(tester.getCenter(_card));
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(const Offset(0, -150));
      await tester.pump();

      expect(angleOf(), lessThan(idle - 0.01)); // 왼쪽(−)으로 더 기울어짐
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('카드 위 스티커는 태그가 아니라 카테고리(아이콘 + 이름)다', (tester) async {
      await _openDetail(tester);

      // 쇼핑 카테고리: 카드 위 스티커 + 정보 카드의 칩, 이름이 두 번 보인다.
      expect(find.text(Category.shopping.label), findsNWidgets(2));
      final sticker = find.ancestor(
        of: find.text(Category.shopping.label).first,
        matching: find.byType(Row),
      );
      expect(sticker, findsWidgets);
      // 태그는 카드 위가 아니라 아래 칩으로만 보인다: 같은 '#태그' 글자가 하나씩만 있다.
      final tagTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.startsWith('#'))
          .toList();
      expect(
        tagTexts.toSet().length,
        tagTexts.length,
        reason: '태그가 중복 표시됨: $tagTexts',
      );
    });
  });

  group('정보 카드·상단 바', () {
    testWidgets('카테고리 버튼은 흰 알약 + 연회색 테두리 + 연필', (tester) async {
      await _openDetail(tester);

      final chip = find.descendant(
        of: find.byKey(const ValueKey('category-chip-5')),
        matching: find.byType(AppChip),
      );
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: chip,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, AppColors.white);
      expect((deco.border! as Border).top.color, AppColors.border);
      expect(
        find.descendant(of: chip, matching: find.byIcon(LucideIcons.pencil)),
        findsOneWidget,
      );
    });

    testWidgets('뒤로 버튼·위치 알약은 원래대로 흰색이다', (tester) async {
      await _openDetail(tester, reader: FakeGalleryReader());

      final pill = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.text('1 / 6'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => (d.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toList();
      expect(pill, contains(AppColors.white));
    });
  });
}
