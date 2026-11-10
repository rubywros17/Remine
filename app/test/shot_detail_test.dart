import 'dart:math' as math;

import 'package:flutter/material.dart';
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

  group('더 보기 버튼 "#태그" 글자색', () {
    testWidgets('"#태그"는 레몬, "모아보기"는 흰색(형광펜 띠 없음)', (tester) async {
      await _openDetail(tester, tags: const ['숙소'], sameTag: 3);

      final tag = tester.widget<Text>(find.byKey(const ValueKey('more-tag')));
      expect(tag.data, '#숙소');
      expect(tag.style!.color, AppColors.lemon);
      expect(
        tester.widget<Text>(find.text(' 모아보기')).style!.color,
        AppColors.white,
      );
    });

    test('레몬 글자는 차콜 위에서 4.5:1 이상', () {
      final ratio =
          (AppColors.lemon.computeLuminance() + 0.05) /
          (AppColors.darkGray.computeLuminance() + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    for (final size in const [Size(360, 800), Size(412, 915)]) {
      testWidgets('태그가 말줄임돼도 레몬색 그대로 · $size', (tester) async {
        const long = '아주아주아주긴관심사태그이름이라서한줄에다안들어가는태그';
        await _openDetail(tester, tags: const [long], sameTag: 3, size: size);

        final tag = tester.widget<Text>(find.byKey(const ValueKey('more-tag')));
        expect(tag.overflow, TextOverflow.ellipsis);
        expect(tag.style!.color, AppColors.lemon);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
