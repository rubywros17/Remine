import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/interests_screen.dart';
import 'package:remine/widgets/capture_thumb.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

/// [dormantDays]가 30일을 넘으면 잊고 있었던 관심사(서버 status와 같은 경계).
Interest _interest({
  String tag = '뜨개질',
  int count = 19,
  int dormantDays = 1,
  int monthCount = 12,
  int recent = 3,
  bool? forgotten,
  List<String> linked = const [],
}) => Interest(
  tag: tag,
  category: Category.shopping,
  forgotten: forgotten ?? dormantDays > Interest.defaultRecentDays,
  captureCount: count,
  dormantDays: dormantDays,
  peakMonth: 9,
  peakMonthCount: monthCount,
  latestMonth: 11,
  latestMonthCount: monthCount,
  recent: [
    for (var i = 0; i < recent; i++)
      InterestCapture(id: i + 1, localAssetId: 'a$i'),
  ],
  linkedTags: linked,
);

Widget _card(
  Interest i, {
  double width = 360,
  double scale = 1.0,
  InterestCardVariant variant = InterestCardVariant.list,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: width - 2 * AppSpacing.screenPadding,
            child: InterestCard(interest: i, onTap: () {}, variant: variant),
          ),
        ),
      ),
    ),
  ),
);

Color _stickerColor(WidgetTester tester, String label) =>
    tester.widget<Sticker>(find.widgetWithText(Sticker, label)).color;

Color _shotsColor(WidgetTester tester) =>
    (tester
                .widget<Container>(find.byKey(const ValueKey('shots-sticker')))
                .decoration!
            as BoxDecoration)
        .color!;

final _now = DateTime(2026, 11, 16, 12);

/// 관심사 [forgotten]개(40일 전~) + [recent]개(1일 전~), 태그마다 3장.
List<ScreenshotItem> _seed({required int forgotten, required int recent}) => [
  for (var k = 0; k < forgotten + recent; k++)
    for (var d = 0; d < 3; d++)
      ScreenshotItem(
        id: k * 10 + d,
        localAssetId: 'a$k$d',
        takenAt: _now.subtract(
          Duration(days: (k < forgotten ? 40 + k : 1 + k) + d),
        ),
        category: Category.shopping,
        tags: [k < forgotten ? '잊은$k' : '요즘$k'],
        summary: '',
      ),
];

Future<void> _openList(
  WidgetTester tester,
  List<ScreenshotItem> seed, {
  Size size = const Size(360, 800),
}) async {
  await tester.pumpWidget(const SizedBox()); // 앞 화면 상태를 버리고 새로 읽게
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RemineScope(
      store: RemineStore(
        FakeScreenshotRepository(now: () => _now, seed: seed),
        now: () => _now,
      ),
      child: const MaterialApp(
        home: Scaffold(
          body: InterestsScreen(),
          bottomNavigationBar: SizedBox(height: 72), // 탭바 자리
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.text('목록 보기').evaluate().isNotEmpty) {
    await tester.tap(find.text('목록 보기'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('관심사 카드 내용', () {
    testWidgets('요즘 모으는 중(30일 이내): 셀라돈 "오늘/어제/N일 전 마지막" + 멘트 1줄', (
      tester,
    ) async {
      for (final (days, text) in [
        (0, '오늘 마지막'),
        (1, '어제 마지막'),
        (30, '30일 전 마지막'),
      ]) {
        await tester.pumpWidget(_card(_interest(dormantDays: days)));
        expect(
          _stickerColor(tester, text),
          AppColors.celadon,
          reason: '$days일',
        );
        expect(_shotsColor(tester), AppColors.celadon);
        expect(find.text('11월에 12번이나 캡처했어요.'), findsOneWidget);
        expect(find.textContaining('잠자는 중'), findsNothing);
        expect(find.textContaining('다시 볼까요?'), findsNothing);
      }
    });

    testWidgets('잊고 있었던 관심사(30일 넘음): 레몬 "N일째 잠자는 중" + 가장 많던 달 멘트 2줄', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_interest(dormantDays: 52)));
      expect(_stickerColor(tester, '52일째 잠자는 중'), AppColors.lemon);
      expect(_shotsColor(tester), AppColors.lemon);
      expect(find.text('9월에 12번이나 캡처했어요.\n다시 볼까요?'), findsOneWidget);
    });

    testWidgets('5번 미만이면 "이나" 없이', (tester) async {
      await tester.pumpWidget(_card(_interest(dormantDays: 52, monthCount: 4)));
      expect(find.text('9월에 4번 캡처했어요.\n다시 볼까요?'), findsOneWidget);
      await tester.pumpWidget(_card(_interest(monthCount: 4)));
      expect(find.text('11월에 4번 캡처했어요.'), findsOneWidget);
    });

    testWidgets('태그가 주인공, 연결 태그·게이지 줄 없음, 스티커 "19 / SHOTS"', (tester) async {
      await tester.pumpWidget(_card(_interest()));
      expect(find.text('#뜨개질'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
      expect(find.text('SHOTS'), findsOneWidget);
      expect(find.text('19'), findsWidgets); // 스티커 + 워터마크
    });

    // 시안 높이(약 140 / 80%)는 실제 폰트로 재는 layout_matrix에서 확인한다(테스트 기본 폰트는 알약이 커진다).
    testWidgets('목록의 요즘 카드는 잊은 카드보다 낮다', (tester) async {
      await tester.pumpWidget(_card(_interest(dormantDays: 52)));
      final forgotten = tester.getSize(find.byType(InterestCard)).height;
      await tester.pumpWidget(_card(_interest()));
      final recent = tester.getSize(find.byType(InterestCard)).height;
      expect(recent, lessThan(forgotten));
    });

    testWidgets('화면 읽기: 상태·태그·잠든 일수·달별 횟수 / 상태·태그·마지막·전체 횟수', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_card(_interest(tag: '코바늘도안', dormantDays: 52)));
      expect(
        find.bySemanticsLabel('잊고 있었던 관심사 #코바늘도안, 52일째 잠자는 중, 9월에 12번 캡처'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _card(_interest(tag: '네일아트', count: 17, dormantDays: 9)),
      );
      expect(
        find.bySemanticsLabel('요즘 모으는 중 #네일아트, 9일 전 마지막, 17번 캡처'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('홈 관심사 카드(예전 모양)', () {
    Widget home(Interest i) => _card(i, variant: InterestCardVariant.home);

    testWidgets('요즘 모으는 중: 셀라돈 "요즘 빠진 것" + 오늘/어제/N일 전 마지막, 멘트 없음', (
      tester,
    ) async {
      for (final (days, text) in [
        (0, '오늘 마지막'),
        (1, '어제 마지막'),
        (12, '12일 전 마지막'), // 예전 7일 경계가 아니라 서버 status 기준
      ]) {
        await tester.pumpWidget(home(_interest(dormantDays: days)));
        expect(find.text(text), findsOneWidget, reason: '$days일');
        expect(_stickerColor(tester, '요즘 빠진 것'), AppColors.celadon);
        expect(_shotsColor(tester), AppColors.celadon);
        expect(find.text('잊었던 관심사'), findsNothing);
        expect(find.textContaining('잠자는 중'), findsNothing);
        expect(find.textContaining('캡처했어요'), findsNothing);
      }
    });

    testWidgets('잊고 있었던 관심사(서버 status): 레몬 스티커 + "N일째 잠자는 중"', (tester) async {
      await tester.pumpWidget(home(_interest(dormantDays: 9, forgotten: true)));
      expect(_stickerColor(tester, '잊었던 관심사'), AppColors.lemon);
      expect(_shotsColor(tester), AppColors.lemon);
      expect(find.text('9일째 잠자는 중'), findsOneWidget);
    });

    testWidgets('#태그 아래 연결 태그 최대 3개, 없으면 줄 없음, 스티커 "19 / SHOTS"', (
      tester,
    ) async {
      await tester.pumpWidget(
        home(_interest(linked: const ['도안', '키링', '코스터', '실'])),
      );
      expect(find.text('#뜨개질'), findsOneWidget);
      expect(find.text('#도안 · #키링 · #코스터'), findsOneWidget);
      expect(find.text('SHOTS'), findsOneWidget);
      expect(find.text('19'), findsWidgets); // 스티커 + 워터마크
      await tester.pumpWidget(home(_interest()));
      expect(find.textContaining(' · '), findsNothing);
    });

    testWidgets('게이지: 많이 캡처할수록 셀라돈 점이 많고, 잊은 건 1칸', (tester) async {
      int on() => find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('gauge-on'),
          )
          .evaluate()
          .length;
      for (final (count, dots) in [(3, 1), (6, 2), (10, 3), (19, 4), (25, 5)]) {
        await tester.pumpWidget(home(_interest(count: count)));
        expect(on(), dots, reason: '$count장');
      }
      await tester.pumpWidget(home(_interest(count: 25, dormantDays: 52)));
      expect(on(), 1);
      // 목록 카드에는 게이지가 없다.
      await tester.pumpWidget(_card(_interest(count: 25)));
      expect(find.byKey(const ValueKey('gauge-on-0')), findsNothing);
    });

    testWidgets('높이 168 이상', (tester) async {
      for (final dormant in const [1, 52]) {
        await tester.pumpWidget(home(_interest(dormantDays: dormant)));
        expect(
          tester.getSize(find.byType(InterestCard)).height,
          greaterThanOrEqualTo(AppInterestCard.homeMinHeight),
        );
      }
    });

    testWidgets('화면 읽기: 상태·태그·횟수·마지막 캡처·함께 캡처한 관심사', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(home(_interest(linked: const ['도안', '코스터'])));
      expect(
        find.bySemanticsLabel(
          '요즘 빠진 것 #뜨개질, 19번 캡처, 어제 마지막, 함께 캡처한 관심사 도안, 코스터',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('관심사 목록 두 섹션', () {
    testWidgets('제목·부제, 잊은 섹션(레몬) 먼저 2개만 → 더 보기로 펼침, 요즘 섹션(셀라돈)', (
      tester,
    ) async {
      // 카드가 모두 그려지게 화면을 길게
      await _openList(
        tester,
        _seed(forgotten: 4, recent: 2),
        size: const Size(412, 1600),
      );

      expect(find.text('관심사'), findsOneWidget);
      expect(find.text('여러 번 캡처한 것들을 모았어요'), findsOneWidget);
      expect(find.text('잊은 관심사'), findsNothing, reason: '옛 제목');
      expect(find.text('잊고 있었던 관심사'), findsOneWidget);
      expect(find.text('요즘 모으는 중'), findsOneWidget);
      expect(find.byType(InterestCard), findsNWidgets(4));
      expect(find.text('잊고 있었던 관심사 2개 더 보기 ↓'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('잊고 있었던 관심사')).dy,
        lessThan(tester.getTopLeft(find.text('요즘 모으는 중')).dy),
      );

      await tester.tap(find.text('잊고 있었던 관심사 2개 더 보기 ↓'));
      await tester.pumpAndSettle();
      expect(find.byType(InterestCard, skipOffstage: false), findsNWidgets(6));
      expect(find.textContaining('더 보기'), findsNothing);
    });

    testWidgets('잊은 관심사가 없으면 점선 안내, 요즘 것이 없으면 섹션째 숨김', (tester) async {
      await _openList(tester, _seed(forgotten: 0, recent: 2));
      expect(find.text('아직 잊고 있었던 관심사가 없어요'), findsOneWidget);
      expect(find.text('요즘 모으는 중'), findsOneWidget);

      await _openList(tester, _seed(forgotten: 1, recent: 0));
      expect(find.text('아직 잊고 있었던 관심사가 없어요'), findsNothing);
      expect(find.text('요즘 모으는 중'), findsNothing);
      expect(find.byType(InterestCard), findsOneWidget);
    });

    for (final (size, recentVisible) in const [
      (Size(412, 915), 2),
      (Size(360, 800), 1),
    ]) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}: 잊은 카드 2개 + 요즘 카드 $recentVisible개가 탭바 위로 보인다',
        (tester) async {
          await _openList(tester, _seed(forgotten: 2, recent: 2), size: size);
          final cards = find.byType(InterestCard);
          expect(
            tester.getBottomLeft(cards.at(1 + recentVisible)).dy,
            lessThanOrEqualTo(size.height - 72),
          );
        },
      );
    }
  });

  group('관심사 목록 다듬기', () {
    testWidgets('요즘 모으는 중도 3개만 → 더 보기 → 접기 ↑로 접히고 섹션 머리가 보인다', (tester) async {
      await _openList(tester, _seed(forgotten: 0, recent: 5));
      expect(find.byType(InterestCard), findsNWidgets(3));
      expect(find.text('요즘 모으는 중 2개 더 보기 ↓'), findsOneWidget);
      BoxDecoration? marker(String text) =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.text(text),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        marker('요즘 모으는 중 2개 더 보기 ↓'),
        highlighterDecoration(color: AppColors.celadon),
        reason: '요즘 섹션은 셀라돈 형광펜',
      );

      await tester.tap(find.text('요즘 모으는 중 2개 더 보기 ↓'));
      await tester.pumpAndSettle();
      expect(find.byType(InterestCard, skipOffstage: false), findsNWidgets(5));
      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      expect(marker('접기 ↑'), highlighterDecoration(color: AppColors.celadon));
      await tester.tap(find.text('접기 ↑'));
      await tester.pumpAndSettle();

      expect(find.byType(InterestCard, skipOffstage: false), findsNWidgets(3));
      expect(find.text('요즘 모으는 중 2개 더 보기 ↓'), findsOneWidget);
      final header = tester.getRect(find.text('요즘 모으는 중'));
      expect(header.top, greaterThanOrEqualTo(0));
      expect(header.bottom, lessThanOrEqualTo(800 - 72));
    });

    testWidgets('잊은 섹션 접기 ↑도 같은 스타일(레몬 형광펜)', (tester) async {
      await _openList(tester, _seed(forgotten: 3, recent: 0));
      await tester.tap(find.text('잊고 있었던 관심사 1개 더 보기 ↓'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('접기 ↑'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(box.decoration, highlighterDecoration());
      await tester.tap(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      expect(find.text('잊고 있었던 관심사 1개 더 보기 ↓'), findsOneWidget);
    });

    testWidgets('다른 탭에 갔다 오면 더 보기·검색이 처음 상태, 태그 화면에 갔다 오면 그대로', (tester) async {
      tester.view.physicalSize = const Size(412, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final active = ValueNotifier(true);
      await tester.pumpWidget(
        RemineScope(
          store: RemineStore(
            FakeScreenshotRepository(
              now: () => _now,
              seed: _seed(forgotten: 4, recent: 1),
            ),
            now: () => _now,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, on, _) => InterestsScreen(active: on),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('잊고 있었던 관심사 2개 더 보기 ↓'));
      await tester.pumpAndSettle();
      expect(find.byType(InterestCard), findsNWidgets(5));

      // 태그 화면에 갔다 오면 그대로
      await tester.tap(find.text('#잊은0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButtonCircle));
      await tester.pumpAndSettle();
      expect(find.byType(InterestCard), findsNWidgets(5));

      // 검색을 열어 둔 채 다른 탭에 갔다 오면 처음 상태
      await tester.tap(find.byIcon(LucideIcons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '잊은');
      await tester.pumpAndSettle();
      active.value = false;
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(InterestCard), findsNWidgets(3));
      expect(find.text('잊고 있었던 관심사 2개 더 보기 ↓'), findsOneWidget);
    });

    testWidgets('검색: 대소문자·띄어쓰기·# 무시, 섹션 유지, 더 보기 없이 전부 / 없으면 안내 / 닫으면 원래대로', (
      tester,
    ) async {
      final seed = [
        ..._seed(forgotten: 3, recent: 0),
        for (final (k, tag) in const ['Nail Art', '네일아트팁'].indexed)
          for (var d = 0; d < 3; d++)
            ScreenshotItem(
              id: 900 + k * 10 + d,
              localAssetId: 'n$k$d',
              takenAt: _now.subtract(Duration(days: 1 + d)),
              category: Category.shopping,
              tags: [tag],
              summary: '',
            ),
      ];
      await _openList(tester, seed, size: const Size(412, 1600));
      expect(find.text('관심사'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.search));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: '검색창을 열면 키보드가 올라온다',
      );

      await tester.enterText(find.byType(TextField), '#nailart');
      await tester.pumpAndSettle();
      expect(find.text('#Nail Art'), findsOneWidget);
      expect(find.text('#네일아트팁'), findsNothing);
      expect(find.text('잊고 있었던 관심사'), findsNothing, reason: '맞는 게 없는 섹션은 숨김');
      expect(find.text('요즘 모으는 중'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '잊 은');
      await tester.pumpAndSettle();
      expect(find.byType(InterestCard), findsNWidgets(3), reason: '더 보기 없이 전부');
      expect(find.textContaining('더 보기'), findsNothing);
      expect(find.text('잊고 있었던 관심사'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '캠핑');
      await tester.pumpAndSettle();
      expect(find.text("'캠핑'와 맞는 관심사가 없어요"), findsOneWidget);
      expect(find.byType(InterestCard), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('관심사'), findsOneWidget);
      expect(find.byType(InterestCard), findsNWidgets(4));
    });
  });

  group('맨 아래로 / 맨 위로 버튼', () {
    final jump = find.byKey(const ValueKey('scroll-jump'));
    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    /// 요즘 관심사 [n]개를 펼친 목록.
    Future<void> openExpanded(WidgetTester tester, int n) async {
      await _openList(tester, _seed(forgotten: 0, recent: n));
      await tester.tap(find.text('요즘 모으는 중 ${n - 3}개 더 보기 ↓'));
      await tester.pumpAndSettle();
    }

    Future<void> scrollDown(WidgetTester tester, double by) async {
      await tester.drag(find.byType(Scrollable).first, Offset(0, -by));
      await tester.pumpAndSettle();
    }

    testWidgets('펼친 카드가 10개 이하면 스크롤해도 안 보인다', (tester) async {
      await openExpanded(tester, 10);
      await scrollDown(tester, 600);
      expect(position(tester).pixels, greaterThan(400));
      expect(jump.hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('맨 아래로'), findsNothing);
    });

    testWidgets('10개 초과 + 화면 절반 이상 내리면 보이고, 접어서 10개 이하가 되면 숨는다', (
      tester,
    ) async {
      await openExpanded(tester, 12);
      expect(jump.hitTestable(), findsNothing, reason: '아직 안 내림');
      await scrollDown(tester, 300);
      expect(jump.hitTestable(), findsNothing, reason: '화면 절반(약 364) 미만');
      await scrollDown(tester, 200);
      expect(jump.hitTestable(), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);
      // 오른쪽 아래, 탭 바(72) 위로 16
      final rect = tester.getRect(jump);
      expect(rect.size, const Size(48, 48));
      expect(rect.right, closeTo(360 - 16, 0.5));
      expect(rect.bottom, closeTo(800 - 72 - 16, 0.5));

      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      expect(jump.hitTestable(), findsNothing);
    });

    testWidgets('누르면 맨 아래로, 맨 아래에서는 위 화살표 → 누르면 맨 위로', (tester) async {
      final semantics = tester.ensureSemantics();
      await openExpanded(tester, 12);
      await scrollDown(tester, 500);
      expect(find.bySemanticsLabel('맨 아래로'), findsOneWidget);

      await tester.tap(jump);
      await tester.pumpAndSettle();
      final p = position(tester);
      expect(p.pixels, p.maxScrollExtent);
      expect(find.byIcon(Icons.keyboard_double_arrow_up), findsOneWidget);
      expect(find.bySemanticsLabel('맨 위로'), findsOneWidget);
      // 마지막 카드가 버튼에 가리지 않는다
      final last = tester.getRect(find.byType(InterestCard).last);
      expect(last.bottom, lessThanOrEqualTo(tester.getRect(jump).top));

      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0);
      expect(jump.hitTestable(), findsNothing);
      semantics.dispose();
    });

    testWidgets('애니메이션 줄이기면 바로 이동한다', (tester) async {
      await openExpanded(tester, 12);
      await scrollDown(tester, 500);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await tester.tap(jump);
      await tester.pump(); // 이동
      await tester.pump(); // 새로 그려진 카드만큼 늘어난 끝까지
      final p = position(tester);
      expect(p.pixels, p.maxScrollExtent);
      expect(tester.hasRunningAnimations, isFalse, reason: '애니메이션 없이 바로');
    });

    testWidgets('아래·위 아이콘 모두 원의 정가운데(오차 0.5 이내)', (tester) async {
      for (final up in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ScrollJumpButton(visible: true, up: up, onTap: () {}),
              ),
            ),
          ),
        );
        final icon = find.byIcon(
          up
              ? Icons.keyboard_double_arrow_up
              : Icons.keyboard_double_arrow_down,
        );
        final c = tester.getCenter(jump);
        final i = tester.getCenter(icon);
        expect((i - c).distance, lessThanOrEqualTo(0.5), reason: 'up=$up');
        expect(tester.getSize(icon), const Size(24, 24));
        expect(tester.getSize(jump), const Size(48, 48));
      }
    });
  });

  group('펼치기·접기 모션', () {
    const more = '요즘 모으는 중 2개 더 보기 ↓';
    double opacityOf(WidgetTester tester, Finder f) => tester
        .widget<Opacity>(
          find.ancestor(of: f, matching: find.byType(Opacity)).first,
        )
        .opacity;

    // 긴 화면: 새 카드가 모두 화면 안이라 차례로 나타난다(화면 밖 카드는 바로 보이는 상태).
    testWidgets('펼치기: 새 카드는 차례로 나타나고, 더 보기가 먼저 사라진 뒤 카드가 다 나오면 접기', (
      tester,
    ) async {
      await _openList(
        tester,
        _seed(forgotten: 0, recent: 5),
        size: const Size(412, 1600),
      );
      await tester.tap(find.text(more));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // 첫 새 카드가 둘째보다 먼저(40ms 간격), 둘 다 아직 다 안 나옴
      final first = opacityOf(tester, find.text('#요즘3'));
      final second = opacityOf(tester, find.text('#요즘4'));
      expect(first, inExclusiveRange(0, 1));
      expect(second, lessThan(first));
      expect(find.text('접기 ↑'), findsNothing, reason: '카드가 다 나온 뒤에');
      expect(opacityOf(tester, find.text(more)), lessThan(1));

      await tester.pumpAndSettle();
      expect(opacityOf(tester, find.text('#요즘3')), 1);
      expect(opacityOf(tester, find.text('#요즘4')), 1);
      expect(find.text(more), findsNothing);
      expect(opacityOf(tester, find.text('접기 ↑')), 1);
    });

    testWidgets('접기: 펼쳤던 카드가 한꺼번에 사라지고 끝나면 빠진다', (tester) async {
      await _openList(tester, _seed(forgotten: 0, recent: 5));
      await tester.tap(find.text(more));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('접기 ↑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final a = opacityOf(tester, find.text('#요즘3'));
      final b = opacityOf(tester, find.text('#요즘4'));
      expect(a, inExclusiveRange(0, 1));
      expect(b, closeTo(a, 0.001), reason: '한꺼번에');

      await tester.pumpAndSettle();
      expect(find.text('#요즘3', skipOffstage: false), findsNothing);
      expect(find.byType(InterestCard, skipOffstage: false), findsNWidgets(3));
      expect(opacityOf(tester, find.text(more)), 1);
    });

    // 긴 화면: 접을 때 머리로 가는 스크롤이 생기지 않게(스크롤이 움직이는 동안은 Flutter가 목록 안 탭을 막는다).
    testWidgets('연타해도 꼬이지 않고 마지막으로 누른 상태로 끝난다', (tester) async {
      await _openList(
        tester,
        _seed(forgotten: 0, recent: 5),
        size: const Size(412, 1600),
      );
      await tester.tap(find.text(more));
      await tester.pump(); // 애니메이션 시작 프레임
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.text(more)); // 사라지는 중 또 누름
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('접기 ↑'));
      await tester.pump(); // 애니메이션 시작 프레임
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(tester, find.text(more)), inExclusiveRange(0, 1));
      await tester.tap(find.text(more)); // 접히는 중에 다시 펼침
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(find.byType(InterestCard, skipOffstage: false), findsNWidgets(5));
      expect(opacityOf(tester, find.text('#요즘3')), 1);
      expect(opacityOf(tester, find.text('#요즘4')), 1);
      expect(find.text('접기 ↑', skipOffstage: false), findsOneWidget);
      expect(find.text(more, skipOffstage: false), findsNothing);
    });

    testWidgets('애니메이션 끄기면 펼치기·접기가 바로 끝난다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openList(tester, _seed(forgotten: 0, recent: 5));
      await tester.tap(find.text(more));
      await tester.pump();
      expect(opacityOf(tester, find.text('#요즘4')), 1);
      expect(find.text('접기 ↑', skipOffstage: false), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.ensureVisible(find.text('접기 ↑'));
      await tester.pump();
      await tester.tap(find.text('접기 ↑'));
      await tester.pump();
      // 접힌 상태가 바로(목록이 짧아져 스크롤 위치가 끝에 맞춰지는 건 Flutter 스크롤 동작이라 확인하지 않는다)
      expect(find.text('#요즘3', skipOffstage: false), findsNothing);
      expect(opacityOf(tester, find.text(more)), 1);
    });
  });

  group('보이는 만큼만 움직이기(4장 섹션 ↔ 38장 섹션)', () {
    const screen = Size(412, 915);
    const viewBottom = 915.0 - 72; // 탭 바 위
    const forgottenMore = '잊고 있었던 관심사 2개 더 보기 ↓';
    const recentMore = '요즘 모으는 중 35개 더 보기 ↓';
    final forgottenReveal = find.byKey(const ValueKey('reveal-forgotten'));
    final recentReveal = find.byKey(const ValueKey('reveal-recent'));

    /// 잊은 관심사 4개 + 요즘 관심사 38개(모두 30일 이내).
    List<ScreenshotItem> seed() => [
      ..._seed(forgotten: 4, recent: 0),
      for (var k = 0; k < 38; k++)
        for (var d = 0; d < 3; d++)
          ScreenshotItem(
            id: 1000 + k * 10 + d,
            localAssetId: 'r$k$d',
            takenAt: _now.subtract(Duration(days: 1 + k % 20, hours: d)),
            category: Category.shopping,
            tags: ['요즘모음$k'],
            summary: '',
          ),
    ];

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    /// [reveal](섹션의 더 보기 부분 + 버튼 자리) 아래 끝이 화면 [y]에 오게 스크롤.
    Future<void> bottomAt(WidgetTester tester, Finder reveal, double y) async {
      final p = position(tester);
      p.jumpTo(p.pixels + tester.getRect(reveal).bottom - y);
      await tester.pump();
    }

    /// 버튼 자리(섹션 아래 끝)의 화면 안 위치. 화면 아래로 나가면 화면 끝.
    double visibleBottom(WidgetTester tester, Finder reveal) =>
        math.min(tester.getRect(reveal).bottom, viewBottom);

    /// 누른 뒤 첫 160ms 동안 화면 안에서 움직인 거리.
    Future<double> moved(
      WidgetTester tester,
      Finder reveal,
      Finder button,
    ) async {
      await tester.tap(button);
      await tester.pump(); // 시작 프레임
      final start = visibleBottom(tester, reveal);
      await tester.pump(const Duration(milliseconds: 160));
      final distance = (visibleBottom(tester, reveal) - start).abs();
      await tester.pumpAndSettle();
      return distance;
    }

    // 같은 화면 위치에서 4장 섹션은 자기 높이(약 300)를, 38장 섹션은 화면 아래 끝(약 385)까지 움직인다.
    // 4장 섹션이 남은 화면보다 짧으면 이만큼(약 27%) 차이가 남는다 → 30% 이내.
    // (작은 화면은 요즘 섹션 버튼이 목록 끝이라 같은 화면 위치에 둘 수 없어 비교하지 않는다.)
    for (final (size, limit) in const [(Size(412, 915), 0.3)]) {
      testWidgets(
        '펼치기 ${size.width.toInt()}×${size.height.toInt()}: 첫 160ms 화면 안 이동 거리 차이 ${(limit * 100).toInt()}% 이내, 끝 상태는 다 펼침',
        (tester) async {
          final bottom = size.height - 72;
          double seen(Finder reveal) =>
              math.min(tester.getRect(reveal).bottom, bottom);
          Future<double> movedHere(Finder reveal, Finder button) async {
            await tester.tap(button);
            await tester.pump(); // 시작 프레임
            final start = seen(reveal);
            await tester.pump(const Duration(milliseconds: 160));
            final distance = (seen(reveal) - start).abs();
            await tester.pumpAndSettle();
            return distance;
          }

          await _openList(tester, seed(), size: size);
          // 잊은 섹션은 목록 맨 위라 더 내려갈 수 없다: 그 자리를 재 두고 요즘 섹션 버튼도 같은 화면 위치에 둔다.
          // 버튼 아래로 움직일 화면이 남게(아래 끝에서 250 위까지만). 큰 폰은 처음 자리 그대로다.
          if (tester.getRect(forgottenReveal).bottom > bottom - 250) {
            await bottomAt(tester, forgottenReveal, bottom - 250);
          }
          final at = tester.getRect(forgottenReveal).bottom;
          final small = await movedHere(
            forgottenReveal,
            find.text(forgottenMore),
          );
          expect(find.text('#잊은3', skipOffstage: false), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text(recentMore),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await bottomAt(tester, recentReveal, at);
          final large = await movedHere(recentReveal, find.text(recentMore));
          expect(small, greaterThan(30));
          expect(
            (large - small).abs() / small,
            lessThan(limit),
            reason: '4장 $small, 38장 $large',
          );

          // 끝 상태: 화면 밖 카드까지 다 보이는 상태
          expect(
            find.byType(InterestCard, skipOffstage: false),
            findsNWidgets(42),
          );
          expect(find.text('접기 ↑', skipOffstage: false), findsNWidgets(2));
          await tester.scrollUntilVisible(
            find.text('#요즘모음37'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          final last = tester.widget<Opacity>(
            find
                .ancestor(
                  of: find.text('#요즘모음37'),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(last.opacity, 1);
        },
      );
    }

    testWidgets(
      '접기: 머리가 멀면 스크롤을 먼저 옮기되 버튼 자리는 그대로, 첫 160ms 이동 거리가 20% 이내로 같다',
      (tester) async {
        await _openList(tester, seed(), size: screen);
        await tester.tap(find.text(forgottenMore));
        await tester.pumpAndSettle();
        await bottomAt(tester, forgottenReveal, viewBottom - 20);
        final small = await moved(
          tester,
          forgottenReveal,
          find.descendant(of: forgottenReveal, matching: find.text('접기 ↑')),
        );
        expect(find.text(forgottenMore), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text(recentMore),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await bottomAt(tester, recentReveal, viewBottom - 20);
        await tester.tap(find.text(recentMore));
        await tester.pumpAndSettle();
        await bottomAt(
          tester,
          recentReveal,
          viewBottom - 20,
        ); // 맨 아래 근처, 머리는 화면 몇 개 위
        final before = visibleBottom(tester, recentReveal);
        await tester.tap(
          find.descendant(of: recentReveal, matching: find.text('접기 ↑')),
        );
        await tester.pump();
        expect(
          visibleBottom(tester, recentReveal),
          closeTo(before, 2),
          reason: '스크롤을 즉시 옮겨도 버튼 자리가 튀지 않는다',
        );
        final start = visibleBottom(tester, recentReveal);
        await tester.pump(const Duration(milliseconds: 160));
        final large = (visibleBottom(tester, recentReveal) - start).abs();
        await tester.pumpAndSettle();

        expect(small, greaterThan(50));
        expect(
          (large - small).abs() / small,
          lessThan(0.2),
          reason: '4장 $small, 38장 $large',
        );
        // 끝 상태: 접히고 섹션 머리가 화면에 보인다
        expect(find.text(recentMore), findsOneWidget);
        expect(
          find.byType(InterestCard, skipOffstage: false),
          findsNWidgets(5),
        );
        final header = tester.getRect(find.text('요즘 모으는 중'));
        expect(header.top, greaterThanOrEqualTo(0));
        expect(header.bottom, lessThanOrEqualTo(viewBottom));
      },
    );
  });

  group('맨 아래로 이동 시간', () {
    test('거리에 비례해 380~700ms', () {
      const screen = 700.0;
      expect(AppScrollJump.travel(0, screen).inMilliseconds, 380);
      expect(AppScrollJump.travel(100, screen).inMilliseconds, 389);
      expect(AppScrollJump.travel(screen * 3, screen).inMilliseconds, 572);
      expect(AppScrollJump.travel(screen * 20, screen).inMilliseconds, 700);
    });

    testWidgets('누르면 380~700ms(+끝 보정) 안에 맨 아래에 닿는다', (tester) async {
      await _openList(tester, _seed(forgotten: 0, recent: 12));
      await tester.tap(find.text('요즘 모으는 중 9개 더 보기 ↓'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final p = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;

      await tester.tap(find.byKey(const ValueKey('scroll-jump')));
      var ms = 0;
      while (p.pixels < p.maxScrollExtent && ms < 2000) {
        await tester.pump(const Duration(milliseconds: 10));
        ms += 10;
      }
      expect(p.pixels, p.maxScrollExtent);
      expect(
        ms,
        inInclusiveRange(
          AppScrollJump.minTravel.inMilliseconds - 20,
          AppScrollJump.maxTravel.inMilliseconds +
              AppScrollJump.settle.inMilliseconds +
              20,
        ),
      );
    });
  });

  group('관심사 카드 레이아웃 매트릭스', () {
    testWidgets(
      '폭 320/360/412 × 글자 1.0/1.3/2.0 × 상태 × 콜라주 0/1/3 × 긴 태그 × 목록/홈(연결 태그 0/2/5): 넘침 없음',
      (tester) async {
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString());
        try {
          for (final width in [320.0, 360.0, 412.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final dormant in [0, 52]) {
                for (final recent in [0, 1, 3]) {
                  for (final tag in ['뜨개질', '아주아주긴관심사이름이라두줄을넘어가는태그']) {
                    for (final (variant, linked) in [
                      (InterestCardVariant.list, 0),
                      for (final n in [0, 2, 5]) (InterestCardVariant.home, n),
                    ]) {
                      await tester.pumpWidget(
                        _card(
                          _interest(
                            tag: tag,
                            dormantDays: dormant,
                            recent: recent,
                            linked: [for (var k = 0; k < linked; k++) '연결$k'],
                          ),
                          width: width,
                          scale: scale,
                          variant: variant,
                        ),
                      );
                      if (errors.isNotEmpty) {
                        fail(
                          '$width/$scale/$dormant/$recent/$tag/${variant.name}/$linked: ${errors.first}',
                        );
                      }
                    }
                  }
                }
              }
            }
          }
        } finally {
          FlutterError.onError = original;
        }
      },
    );

    for (final width in const [360.0, 412.0]) {
      testWidgets(
        'SHOTS 스티커: 맨 앞 사진 오른쪽 위에 걸치고, 카드 안쪽에 있고, 글자와 안 겹친다 (폭 $width)',
        (tester) async {
          for (final scale in const [1.0, 1.3]) {
            for (final dormant in const [1, 52]) {
              for (final (recent, variant) in [
                for (final r in const [1, 3])
                  for (final v in InterestCardVariant.values) (r, v),
              ]) {
                await tester.pumpWidget(
                  _card(
                    _interest(
                      dormantDays: dormant,
                      recent: recent,
                      linked: const ['도안', '키링', '코스터'],
                    ),
                    width: width,
                    scale: scale,
                    variant: variant,
                  ),
                );
                final why = '$width/$scale/$dormant/$recent/${variant.name}';
                final card = tester.getRect(find.byType(InterestCard));
                final c = tester.getCenter(
                  find.byKey(const ValueKey('shots-sticker')),
                );
                const r = AppInterestCard.shotsSize / 2;
                final sticker = Rect.fromCircle(center: c, radius: r);
                // 카드 가장자리에서 안쪽 여백 이상 떨어져 잘리지 않는다.
                final inside = card.deflate(
                  AppInterestCard.shotsEdgeInset - 0.5,
                );
                expect(inside.contains(sticker.topLeft), isTrue, reason: why);
                expect(
                  inside.contains(sticker.bottomRight),
                  isTrue,
                  reason: why,
                );
                // 맨 앞 사진(마지막에 그려진 썸네일)의 오른쪽 위에 걸친다.
                final front = tester.getRect(find.byType(CaptureThumb).last);
                expect(sticker.overlaps(front), isTrue, reason: why);
                expect(c.dx, greaterThan(front.center.dx), reason: why);
                expect(c.dy, lessThan(front.center.dy), reason: why);
                // 태그 제목·상태 스티커와 겹치지 않는다.
                for (final f in [find.text('#뜨개질'), find.byType(Sticker)]) {
                  expect(
                    sticker.overlaps(tester.getRect(f)),
                    isFalse,
                    reason: why,
                  );
                }
              }
            }
          }
        },
      );
    }
  });
}
