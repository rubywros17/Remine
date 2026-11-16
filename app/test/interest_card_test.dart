import 'package:flutter/material.dart';
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
}) => Interest(
  tag: tag,
  category: Category.shopping,
  forgotten: dormantDays > Interest.defaultRecentDays,
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
);

Widget _card(
  Interest i, {
  double width = 360,
  double scale = 1.0,
  bool? compact,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: width - 2 * AppSpacing.screenPadding,
            child: InterestCard(
              interest: i,
              onTap: () {},
              compact: compact ?? !i.forgotten,
            ),
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

    testWidgets('목록의 요즘 카드는 잊은 카드보다 낮다(약 80%), 홈 카드는 그대로', (tester) async {
      await tester.pumpWidget(_card(_interest(dormantDays: 52)));
      final forgotten = tester.getSize(find.byType(InterestCard)).height;
      await tester.pumpWidget(_card(_interest()));
      final recent = tester.getSize(find.byType(InterestCard)).height;
      expect(recent / forgotten, closeTo(0.8, 0.05));
      await tester.pumpWidget(_card(_interest(), compact: false));
      expect(tester.getSize(find.byType(InterestCard)).height, forgotten);
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

  group('관심사 카드 레이아웃 매트릭스', () {
    testWidgets(
      '폭 320/360/412 × 글자 1.0/1.3/2.0 × 상태 × 콜라주 0/1/3 × 긴 태그: 넘침 없음',
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
                    await tester.pumpWidget(
                      _card(
                        _interest(
                          tag: tag,
                          dormantDays: dormant,
                          recent: recent,
                        ),
                        width: width,
                        scale: scale,
                      ),
                    );
                    if (errors.isNotEmpty) {
                      fail(
                        '$width/$scale/$dormant/$recent/$tag: ${errors.first}',
                      );
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
              for (final recent in const [1, 3]) {
                await tester.pumpWidget(
                  _card(
                    _interest(dormantDays: dormant, recent: recent),
                    width: width,
                    scale: scale,
                  ),
                );
                final why = '$width/$scale/$dormant/$recent';
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
