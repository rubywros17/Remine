import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/helpers.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/tag_screen.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

final _now = DateTime(2026, 11, 10, 12);

Future<void> _openDetail(
  WidgetTester tester, {
  String? sourceApp,
  List<String> tags = const ['가디건', '재입고'],
  int sameTag = 0,
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final shot = ScreenshotItem(
    id: 1,
    localAssetId: 'a',
    takenAt: DateTime(2026, 11, 6, 13, 58),
    category: Category.shopping,
    summary: '가디건 재입고',
    tags: tags,
    sourceApp: sourceApp,
  );
  // 같은 대표 태그를 가진 다른 캡처(더 오래된 것) — "더 보기" 개수.
  final others = [
    for (var i = 0; i < sameTag; i++)
      ScreenshotItem(
        id: 100 + i,
        localAssetId: 'o$i',
        takenAt: DateTime(2026, 11, 1, 9, i),
        category: Category.place,
        tags: [tags.first],
      ),
  ];
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(
        now: () => _now,
        seed: [shot, ...others],
      ),
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

  testWidgets('해시태그는 칩이 아니라 레몬 형광펜 글자', (tester) async {
    await _openDetail(tester);

    expect(find.byType(HighlighterText), findsNWidgets(2));
    expect(find.text('#가디건'), findsOneWidget);
  });

  testWidgets('캡처 위 이름표는 카테고리 색 배경', (tester) async {
    await _openDetail(tester);

    final sticker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('category-sticker')),
    );
    expect(
      (sticker.decoration as BoxDecoration).color,
      AppCategoryColors.of(Category.shopping),
    );
  });

  test('7개 카테고리 색 모두 차콜 배경 위에서 보이고(3:1 이상), #111 글자도 읽힌다(4.5:1 이상)', () {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    for (final c in Category.values) {
      final color = AppCategoryColors.of(c);
      expect(contrast(color, AppColors.darkGray), greaterThan(3), reason: '$c');
      expect(contrast(color, AppColors.ink), greaterThan(4.5), reason: '$c');
    }
  });

  testWidgets('더 보기 버튼: 차콜 64 · "#태그 모아보기" / "같은 관심사 캡처 N장" · 누르면 태그 화면', (
    tester,
  ) async {
    await _openDetail(tester, tags: const ['숙소'], sameTag: 7);

    final button = find.byKey(const ValueKey('more-button'));
    final box = tester.widget<Container>(
      find.descendant(of: button, matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).color, AppColors.darkGray);
    expect(tester.getSize(button).height, 64);
    expect(find.text('#숙소'), findsNWidgets(2)); // 해시태그 + 버튼
    expect(find.text(' 모아보기'), findsOneWidget);
    expect(find.text('같은 관심사 캡처 7장'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(TagScreen), findsOneWidget);
  });

  for (final (others, thumbs) in [(0, 0), (1, 1), (2, 2), (3, 3), (5, 3)]) {
    testWidgets('같은 관심사 캡처 $others장 → 썸네일 $thumbs장(지금 캡처 제외)', (tester) async {
      await _openDetail(tester, tags: const ['숙소'], sameTag: others);

      final shown = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('more-thumb-'),
      );
      expect(shown, findsNWidgets(thumbs));
      expect(find.byKey(const ValueKey('more-thumb-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('more-button')),
        others == 0 ? findsNothing : findsOneWidget,
      );
    });
  }

  for (final size in const [Size(360, 800), Size(412, 915)]) {
    testWidgets('태그가 길면 태그만 말줄임, "모아보기"는 다 보인다 · $size', (tester) async {
      const long = '아주아주아주긴관심사태그이름이라서한줄에다안들어가는태그';
      await _openDetail(tester, tags: const [long], sameTag: 12, size: size);

      final rest = find.text(' 모아보기');
      expect(rest, findsOneWidget);
      final painter = TextPainter(
        text: TextSpan(text: ' 모아보기', style: tester.widget<Text>(rest).style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(tester.getSize(rest).width, greaterThanOrEqualTo(painter.width));
      final tag = tester.widget<Text>(find.text('#$long').last);
      expect(tag.overflow, TextOverflow.ellipsis);
      expect(
        find.byKey(const ValueKey('more-thumb-111')),
        findsOneWidget,
      ); // 최신 1장
      expect(tester.takeException(), isNull);
    });
  }

  test('출처 표기: 자주 나오는 앱만 띄어 쓰고, 사전에 없으면 대문자 그대로', () {
    expect(sourceAppLabel('KakaoMap'), 'KAKAO MAP');
    expect(sourceAppLabel('NAVERMAP'), 'NAVER MAP');
    expect(sourceAppLabel('NMap'), 'NAVER MAP');
    expect(sourceAppLabel('Naver Map'), 'NAVER MAP');
    expect(sourceAppLabel('Instagram'), 'INSTAGRAM');
    expect(sourceAppLabel('29CM'), '29CM');
  });

  testWidgets('출처 칩도 사전 표기를 쓴다', (tester) async {
    await _openDetail(tester, sourceApp: 'KAKAOMAP');

    expect(find.text('KAKAO MAP'), findsOneWidget);
  });

  testWidgets('캡처 카드는 흰 테두리 대신 그림자·레몬 빛 번짐·1px 흰 10% 윤곽', (tester) async {
    await _openDetail(tester);

    final hero = find.descendant(
      of: find.byType(PageView),
      matching: find.byType(Hero),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: hero, matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration as BoxDecoration)
        .toList();
    final shadowed = boxes.firstWhere((d) => d.boxShadow != null);
    expect(shadowed.boxShadow!.map((s) => s.color), [
      AppDetail.cardGlow,
      AppDetail.cardShadow,
    ]);
    expect(
      boxes.where((d) => d.border?.top.color == AppDetail.cardOutline),
      hasLength(1),
    );
    // 사진(내용)과 카드 가장자리 사이에 흰 패딩이 없다(회전 전 크기로 비교).
    final clip = find.descendant(of: hero, matching: find.byType(ClipRRect));
    expect(tester.getSize(clip.first), tester.getSize(hero));
  });

  group('더 보기 버튼 "#태그" 형광펜', () {
    Finder highlight() => find.byKey(const ValueKey('more-tag-highlight'));
    Finder band() => find.descendant(
      of: highlight(),
      matching: find.byKey(const ValueKey('highlight-band')),
    );
    Finder tagText() =>
        find.descendant(of: highlight(), matching: find.byType(Text));

    /// 화면상 글자 기준선 y와 글자 크기.
    (double, double) baselineOf(WidgetTester tester) {
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(of: tagText(), matching: find.byType(RichText)),
      );
      final top = p.localToGlobal(Offset.zero).dy;
      // 그려진 문단과 같은 글자·배율로 기준선을 잰다(레이아웃 밖에서는 RenderParagraph에 직접 물을 수 없다).
      final painter = TextPainter(
        text: p.text,
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
        maxLines: 1,
      )..layout();
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      painter.dispose();
      return (top + baseline, p.textScaler.scale(p.text.style!.fontSize!));
    }

    testWidgets('"#태그"에만 불투명 레몬 띠(두께 6), "모아보기"에는 없다', (tester) async {
      await _openDetail(tester, tags: const ['숙소'], sameTag: 3);

      expect(tester.widget<ColoredBox>(band()).color, AppColors.lemon);
      expect(tester.getSize(band()).height, 6);
      expect(
        find.descendant(of: highlight(), matching: find.text('#숙소')),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text(' 모아보기'), matching: highlight()),
        findsNothing,
      );
    });

    testWidgets('띠는 글자 아래 끝에 붙고, 글자와 겹쳐도 글자 높이의 10% 이내', (tester) async {
      await _openDetail(tester, tags: const ['숙소'], sameTag: 3);

      final (baseline, fontSize) = baselineOf(tester);
      final top = tester.getRect(band()).top;
      final overlap = math.max(0.0, baseline - top);
      expect(overlap, lessThanOrEqualTo(fontSize * 0.1));
      expect(top - baseline, lessThan(2), reason: '띠가 글자에서 떨어져 있다');
    });

    test('흰 글자는 차콜 위에서 4.5:1 이상', () {
      final ratio =
          (AppColors.white.computeLuminance() + 0.05) /
          (AppColors.darkGray.computeLuminance() + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    for (final size in const [Size(360, 800), Size(412, 915)]) {
      testWidgets('태그가 말줄임돼도 띠가 말줄임 끝까지(글자 폭과 같다) · $size', (tester) async {
        const long = '아주아주아주긴관심사태그이름이라서한줄에다안들어가는태그';
        await _openDetail(tester, tags: const [long], sameTag: 3, size: size);

        final b = tester.getRect(band());
        final t = tester.getRect(tagText());
        expect(b.left, t.left);
        expect(b.width, t.width);
        expect(tester.getRect(find.text(' 모아보기')).left, b.right);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
