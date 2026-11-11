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

Interest _interest({
  String tag = '뜨개질',
  int count = 19,
  int dormantDays = 1,
  List<String> linked = const ['도안', '코스터'],
  int recent = 3,
}) => Interest(
  tag: tag,
  category: Category.shopping,
  captureCount: count,
  spanDays: 14,
  dormantDays: dormantDays,
  recent: [
    for (var i = 0; i < recent; i++)
      InterestCapture(id: i + 1, localAssetId: 'a$i'),
  ],
  linkedTags: linked,
);

Widget _card(Interest i, {double width = 360, double scale = 1.0}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width - 2 * AppSpacing.screenPadding,
                child: InterestCard(interest: i, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );

int _gaugeOn(WidgetTester tester) => find
    .byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('gauge-on'),
    )
    .evaluate()
    .length;

Color _stickerColor(WidgetTester tester, String label) =>
    tester.widget<Sticker>(find.widgetWithText(Sticker, label)).color;

/// 카드 안에 레몬색 테두리(Border.all)가 있는지.
bool _hasLemonBorder(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((b) => b.decoration)
    .whereType<BoxDecoration>()
    .any(
      (d) =>
          d.border is Border &&
          (d.border! as Border).top.color == AppColors.lemon,
    );

void main() {
  group('관심사 카드 내용', () {
    testWidgets('7일 미만: 셀라돈 "요즘 빠진 것" + 오늘/어제/N일 전 마지막, 테두리 없음', (
      tester,
    ) async {
      for (final (days, text) in [
        (0, '오늘 마지막'),
        (1, '어제 마지막'),
        (3, '3일 전 마지막'),
      ]) {
        await tester.pumpWidget(_card(_interest(dormantDays: days)));
        expect(find.text(text), findsOneWidget, reason: '$days일');
        expect(_stickerColor(tester, '요즘 빠진 것'), AppColors.celadon);
        expect(find.text('잊은 관심사'), findsNothing);
        expect(
          find.textContaining('잠자는 중'),
          findsNothing,
          reason: '"0일째 잠자는 중" 같은 문구 없음',
        );
        expect(_hasLemonBorder(tester), isFalse);
      }
    });

    testWidgets('7일 이상: 레몬 "잊은 관심사" + "N일째 잠자는 중", 테두리는 다른 카드처럼 없음', (
      tester,
    ) async {
      await tester.pumpWidget(_card(_interest(dormantDays: 9)));
      expect(_stickerColor(tester, '잊은 관심사'), AppColors.lemon);
      expect(find.text('9일째 잠자는 중'), findsOneWidget);
      expect(_hasLemonBorder(tester), isFalse);
      final shots = tester.widget<Container>(
        find.byKey(const ValueKey('shots-sticker')),
      );
      expect((shots.decoration! as BoxDecoration).color, AppColors.lemon);
    });

    testWidgets('태그가 주인공, 그 아래 linkedTags 최대 3개, 스티커 "19 / SHOTS"(셀라돈)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(_interest(linked: ['도안', '코스터', '실', '바늘'])),
      );
      expect(find.text('#뜨개질'), findsOneWidget);
      expect(find.text('#도안 · #코스터 · #실'), findsOneWidget);
      expect(find.text('SHOTS'), findsOneWidget);
      expect(find.text('19'), findsWidgets); // 스티커 + 워터마크
      final shots = tester.widget<Container>(
        find.byKey(const ValueKey('shots-sticker')),
      );
      expect((shots.decoration! as BoxDecoration).color, AppColors.celadon);

      await tester.pumpWidget(_card(_interest(linked: const [])));
      expect(find.textContaining(' · '), findsNothing);
    });

    testWidgets('게이지: 많이 캡처할수록 셀라돈 점이 많고, 잊은 건 1칸', (tester) async {
      for (final (count, on) in [(3, 1), (6, 2), (10, 3), (19, 4), (25, 5)]) {
        await tester.pumpWidget(_card(_interest(count: count)));
        expect(_gaugeOn(tester), on, reason: '$count장');
      }
      await tester.pumpWidget(_card(_interest(count: 25, dormantDays: 8)));
      expect(_gaugeOn(tester), 1);
    });

    testWidgets('화면 읽기: 상태·태그·기간·횟수·마지막 캡처·함께 캡처한 관심사', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_card(_interest()));
      expect(
        find.bySemanticsLabel(
          '요즘 빠진 것 뜨개질, 2주 동안 19번 캡처, 어제 마지막, 함께 캡처한 관심사 도안, 코스터',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('관심사 카드 레이아웃 매트릭스', () {
    testWidgets(
      '폭 320/360/412 × 글자 1.0/1.3/2.0 × 상태 × linkedTags 0/2/5 × 콜라주 0/1/3 × 긴 태그: 넘침 없음',
      (tester) async {
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString());
        try {
          for (final width in [320.0, 360.0, 412.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final dormant in [0, 12]) {
                for (final linked in [0, 2, 5]) {
                  for (final recent in [0, 1, 3]) {
                    for (final tag in ['뜨개질', '아주아주긴관심사이름이라두줄을넘어가는태그']) {
                      await tester.pumpWidget(
                        _card(
                          _interest(
                            tag: tag,
                            dormantDays: dormant,
                            linked: [for (var k = 0; k < linked; k++) '연결$k'],
                            recent: recent,
                          ),
                          width: width,
                          scale: scale,
                        ),
                      );
                      if (errors.isNotEmpty) {
                        fail(
                          '$width/$scale/$dormant/$linked/$recent/$tag: ${errors.first}',
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
            for (final dormant in const [1, 12]) {
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

    testWidgets('360×800, 글자 1.0: 관심사 탭에 카드 3장이 탭바 위로 다 보인다', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime(2026, 10, 26, 12);
      final seed = [
        for (final (k, tag) in ['뜨개질', '캠핑', '향수'].indexed)
          for (var d = 0; d < 3; d++)
            ScreenshotItem(
              id: k * 10 + d,
              localAssetId: 'a$k$d',
              takenAt: now.subtract(Duration(days: d + k * 4)),
              category: Category.shopping,
              tags: [tag],
              summary: '',
            ),
      ];
      await tester.pumpWidget(
        RemineScope(
          store: RemineStore(
            FakeScreenshotRepository(now: () => now, seed: seed),
            now: () => now,
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
      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();

      final cards = find.byType(InterestCard);
      expect(cards, findsNWidgets(3));
      expect(tester.getBottomLeft(cards.at(2)).dy, lessThanOrEqualTo(800 - 72));
    });
  });
}
