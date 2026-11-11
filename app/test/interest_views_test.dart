import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remine/core/helpers.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/detail_screen.dart';
import 'package:remine/screens/interests_screen.dart';
import 'package:remine/screens/tag_screen.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/interest_brain_map.dart';
import 'package:remine/widgets/sync_banner.dart';

import 'support/fake_remote.dart';

final _now = DateTime(2026, 10, 26, 12);

ScreenshotItem _shot(
  int id,
  int daysAgo,
  Category category,
  List<String> tags,
) => ScreenshotItem(
  id: id,
  localAssetId: 'a$id',
  takenAt: _now.subtract(Duration(days: daysAgo)),
  category: category,
  tags: tags,
  summary: '캡처 $id',
);

/// 뜨개질: 최근 2주 4장(쇼핑·정보) + 그 전 2장(문화생활). 뜨개질·도안이 캡처 1~3을 공유한다.
/// 가방은 마지막 캡처가 9일 전이라 "잊은 관심사".
final _seed = [
  _shot(1, 1, Category.shopping, ['뜨개질', '도안']),
  _shot(2, 2, Category.info, ['뜨개질', '도안']),
  _shot(3, 3, Category.shopping, ['뜨개질', '도안']),
  _shot(9, 4, Category.info, ['뜨개질']),
  _shot(4, 9, Category.shopping, ['가방']),
  _shot(5, 10, Category.shopping, ['가방']),
  _shot(6, 11, Category.shopping, ['가방']),
  _shot(7, 20, Category.entertainment, ['뜨개질']),
  _shot(8, 30, Category.entertainment, ['뜨개질']),
];

Widget _scoped(
  Widget child, {
  List<ScreenshotItem>? seed,
  bool reduceMotion = false,
}) {
  final store = RemineStore(
    FakeScreenshotRepository(now: () => _now, seed: seed ?? _seed),
    now: () => _now,
  );
  return RemineScope(
    store: store,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: child,
      ),
    ),
  );
}

void main() {
  group('홈 진행 배너 → 분석 화면', () {
    testWidgets('정리 중 배너를 누르면 진행 화면, 돌아오면 배너 그대로, 보는 중에 끝나면 완료 상태', (
      tester,
    ) async {
      final rig = (await tester.runAsync(
        () => SyncRig.create(
          photos: const [],
          client: RecordingClient(
            responder: (r) => Completer<http.StreamedResponse>().future,
          ),
        ),
      ))!;
      rig.status.begin(10);
      rig.status.advance(3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(children: [SyncBanner(remote: rig.remote)]),
          ),
        ),
      );

      final banner = find.bySemanticsLabel(RegExp('분석 진행 화면 열기'));
      final semantics = tester.ensureSemantics();
      expect(banner, findsOneWidget);
      semantics.dispose();
      await tester.tap(find.textContaining('새 캡처를 정리하는 중이에요'));
      // 분석 화면은 진행 중 막대가 계속 움직여 settle되지 않으므로 전환 시간만 흘려보낸다.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AnalysisScreen), findsOneWidget);

      await tester.ensureVisible(find.text('홈에서 먼저 볼래요'));
      await tester.tap(find.text('홈에서 먼저 볼래요'));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisScreen), findsNothing);
      expect(
        find.textContaining('3/10장'),
        findsOneWidget,
        reason: '아직 정리 중이라 배너가 남는다',
      );

      await tester.tap(find.textContaining('새 캡처를 정리하는 중이에요'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      rig.status.advance(7);
      rig.status.finish();
      await tester.pump();
      expect(
        find.text('홈에서 둘러보기'),
        findsOneWidget,
        reason: '보는 중에 끝나면 그 자리에서 완료 상태',
      );
      await tester.ensureVisible(find.text('홈에서 둘러보기'));
      await tester.tap(find.text('홈에서 둘러보기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('새 캡처를 정리하는 중이에요'), findsNothing);
    });
  });

  group('태그 모아보기', () {
    testWidgets('카테고리 상관없이 그 태그 캡처 전부, 최근 2주가 먼저이고 숫자 두 개를 같이 보여 준다', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(const TagScreen(tag: '뜨개질')));
      await tester.pumpAndSettle();

      expect(find.text('#뜨개질'), findsOneWidget);
      expect(find.text('최근 2주 4장 · 전체 6장 · 어제 마지막'), findsOneWidget);
      expect(find.text('4'), findsOneWidget, reason: '오른쪽 위 큰 숫자 = 최근 2주 장수');
      expect(find.bySemanticsLabel('#뜨개질 최근 2주 4장'), findsOneWidget);
      expect(find.bySemanticsLabel('최근 14일 중 4일 캡처'), findsOneWidget);
      expect(find.text('오늘'), findsOneWidget);
      expect(find.text('10.13'), findsOneWidget, reason: '막대 시작 날짜 = 13일 전');
      // 1·2·3·4일 전 1장씩 → 최근 3일(오늘 포함) 2장 = 그 전 4일 2장, 몰아서·오늘 아님 → 그 외
      expect(
        find.text('2주 동안 꾸준히 모았어요').evaluate().length +
            find.text('2주 중 4일이나 캡처했어요. 진심이네요').evaluate().length,
        1,
      );
      expect(find.text('최근 2주'), findsOneWidget);
      expect(find.text('그 전'), findsOneWidget);
      for (final id in [1, 2, 3, 9, 7, 8]) {
        expect(
          find.byKey(ValueKey('tile-$id')),
          findsOneWidget,
          reason: '캡처 $id',
        );
      }
      expect(find.byKey(const ValueKey('tile-4')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('tile-7')));
      // 최근 구역(1·2·3)이 그 전 구역(7·8)보다 위에 있다
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('tile-3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('tile-7'))).dy),
      );
    });

    test('날짜별 개수는 달력 날짜로 세고 오늘이 마지막 칸, 기간 밖은 버린다', () {
      final items = [
        _shot(1, 0, Category.etc, []),
        _shot(2, 0, Category.etc, []),
        _shot(3, 1, Category.etc, []),
        _shot(4, 13, Category.etc, []),
        _shot(5, 14, Category.etc, []),
      ];
      final counts = dailyCounts(items, _now, 14);
      expect(counts.length, 14);
      expect(counts.last, 2);
      expect(counts[12], 1);
      expect(counts.first, 1);
      expect(counts.fold(0, (a, b) => a + b), 4);
      // 24시간이 안 지났어도 자정을 넘기면 어제 칸이다
      expect(
        dailyCounts(
          [_shot(6, 0, Category.etc, [])],
          DateTime(2026, 10, 27, 0, 30),
          14,
        ).last,
        0,
      );
    });

    group('해석 문장', () {
      // 14칸, 마지막 칸이 오늘(_now = 10.26)
      List<int> days(Map<int, int> daysAgo) =>
          List.generate(14, (i) => daysAgo[13 - i] ?? 0);

      /// 그 상황의 문구 중 하나가 자리표시 없이 채워졌는지.
      void expectFrom(
        String key,
        ({InsightId id, String text})? insight,
        List<String> filled,
      ) {
        expect(insight?.id.$1, key);
        final line = insight!.text;
        expect(filled, contains(line), reason: key);
        expect(line, isNot(contains('{')));
        expect(line, isNot(anyOf(contains('캡쳐'), contains('찍었'))));
      }

      test('잠잠: 마지막 캡처가 7일 이상 전이면 가장 많던 날·잠잠한 일수', () {
        // 9일 전 3장, 7일 전 1장 → 7일째 잠잠, 10월 17일에 가장
        final c = days({9: 3, 7: 1});
        expectFrom('quiet', tagInsight('뜨개질', c, _now), [
          '10월 17일엔 푹 빠져 있었는데, 요즘 7일째 조용하네요',
          '한창일 땐 하루 3장씩 캡처했는데, 잊고 있었나요?',
          '7일째 소식이 없어요. 아직 관심 있죠?',
        ]);
      });

      test('"하루 N장씩" 문구는 가장 많던 날이 2장 이상일 때만', () {
        Set<String?> lines(List<int> c) => {
          for (final pick in [0, 1, 2, 3, 4, 5])
            tagInsight('뜨개질', c, _now, pick: pick)?.text,
        };
        final one = lines(days({9: 1, 7: 1}));
        expect(one, hasLength(2));
        expect(one.where((t) => t!.contains('장씩')), isEmpty);
        expect(
          lines(days({9: 2, 7: 1})),
          contains('한창일 땐 하루 2장씩 캡처했는데, 잊고 있었나요?'),
        );
        // 쓸 수 있는 문구가 2개뿐이어도 직전 문구는 피한다
        expect(
          tagInsight('뜨개질', days({9: 1, 7: 1}), _now, avoid: ('quiet', 0))?.id,
          ('quiet', 2),
        );
      });

      test('마지막 캡처 3~6일 전은 패턴 상황으로: 몰아서 또는 그 외', () {
        expect(tagInsight('뜨개질', days({4: 3}), _now)?.id.$1, 'burst');
        expect(tagInsight('뜨개질', days({4: 1, 9: 1}), _now)?.id.$1, 'steady');
      });

      test('그 외의 "가장 푹 빠져" 문구는 가장 많던 날이 2장 이상일 때만', () {
        Set<String?> lines(List<int> c) => {
          for (final pick in [0, 1, 2, 3, 4, 5])
            tagInsight('뜨개질', c, _now, pick: pick)?.text,
        };
        final two = days({1: 2, 3: 1, 4: 1, 6: 1, 9: 1});
        expect(tagInsight('뜨개질', two, _now)?.id.$1, 'steady');
        expect(lines(two), contains('10월 25일에 가장 푹 빠져 있었어요'));
        final one = days({1: 1, 3: 1, 4: 1, 6: 1, 9: 1});
        expect(tagInsight('뜨개질', one, _now)?.id.$1, 'steady');
        expect(lines(one), hasLength(2));
        expect(lines(one).where((t) => t!.contains('가장')), isEmpty);
      });

      group('그 외 문구 조건', () {
        Set<String?> lines(List<int> c) => {
          for (final pick in [0, 1, 2, 3, 4, 5])
            tagInsight('뜨개질', c, _now, pick: pick)?.text,
        };
        const lastCaptureLines = {
          '10월 22일에 마지막으로 캡처했어요',
          '10월 22일에 눈여겨봤던 관심사예요',
        };

        test('1장: 마지막 캡처 날의 기본 문구만', () {
          expect(lines(days({4: 1})), lastCaptureLines);
        });

        test('2일 × 1장: 기본 문구만, 날짜는 가장 많던 날이 아니라 마지막 캡처 날', () {
          expect(lines(days({4: 1, 9: 1})), lastCaptureLines);
        });

        test('3일 이상: 꾸준히·N일이나만, 기본 문구는 안 나온다', () {
          expect(lines(days({4: 1, 6: 1, 9: 1})), {
            '2주 동안 꾸준히 모았어요',
            '2주 중 3일이나 캡처했어요. 진심이네요',
          });
        });

        test('3일 이상 + 가장 많던 날 2장: 가장 많던 날 문구도 나온다', () {
          expect(lines(days({4: 1, 6: 2, 9: 1, 10: 1, 11: 1})), {
            '2주 동안 꾸준히 모았어요',
            '2주 중 5일이나 캡처했어요. 진심이네요',
            '10월 20일에 가장 푹 빠져 있었어요',
          });
        });

        test('문구 글자를 바꿔도 조건은 그대로: "꾸준히"가 없어도 3일 미만이면 안 나온다', () {
          const edited = {
            'steady': [
              Phrase('차곡차곡 모았어요', minDays: 3),
              Phrase('기본 문구', fallback: true),
            ],
          };
          String? line(List<int> c) =>
              tagInsight('뜨개질', c, _now, phrases: edited)?.text;
          expect(line(days({4: 1})), '기본 문구');
          expect(line(days({4: 1, 6: 1, 9: 1})), '차곡차곡 모았어요');
          // 전부 조건에 걸려도 죽지 않고 문장만 없다
          expect(
            tagInsight(
              '뜨개질',
              days({4: 1}),
              _now,
              phrases: const {
                'steady': [Phrase('차곡차곡 모았어요', minDays: 3)],
              },
            ),
            isNull,
          );
        });

        test('기본 문구 안에서도 직전 문구는 피한다', () {
          final seen = tagInsight('뜨개질', days({4: 1}), _now, pick: 0)!;
          final next = tagInsight(
            '뜨개질',
            days({4: 1}),
            _now,
            pick: 0,
            avoid: seen.id,
          )!;
          expect(next.id.$1, 'steady');
          expect(next.id, isNot(seen.id));
          expect(lastCaptureLines, contains(next.text));
        });
      });

      test('마지막 캡처로부터 지난 날짜 경계: 2·3·6·7·13·14일', () {
        String? at(int daysAgo) => tagInsight(
          '뜨개질',
          days({daysAgo: 1}),
          _now,
          lastCapture: _now.subtract(Duration(days: daysAgo)),
        )?.id.$1;

        expect(at(2), 'new', reason: '최근 3일에만 있음');
        expect(at(3), 'steady', reason: '최근 3일 밖이라 새로 생김이 아니다');
        expect(at(6), 'steady');
        expect(at(7), 'quiet', reason: '카드 "잊은 관심사"와 같은 7일');
        expect(at(13), 'quiet');
        expect(at(14), 'dormant', reason: '14일 전은 막대 기간 밖');
      });

      test('오래 잠잠: 기간 안 0장이면 전체 목록의 마지막 캡처 기준, 그것도 없으면 null', () {
        expectFrom(
          'dormant',
          tagInsight(
            '뜨개질',
            List.filled(14, 0),
            _now,
            lastCapture: DateTime(2026, 10, 6, 23),
          ),
          ['마지막 캡처가 20일 전이에요. 다시 꺼내 볼까요?', '2주 넘게 소식이 없어요. 아직 좋아하죠?'],
        );
      });

      test('새로 생김: 최근 3일에만 있으면 "다시 늘어남"이 아니다', () {
        final c = days({0: 1, 2: 2});
        expectFrom('new', tagInsight('뜨개질', c, _now), [
          '오, 새로운 관심사가 생겼네요!',
          '요즘 여기에 꽂혔군요. 앞으로가 기대돼요',
        ]);
      });

      test('다시 늘어남은 그 전 4일보다 앞에 캡처가 있어야: 그 전 4일에만 있으면 아래 상황으로', () {
        // 최근 3일 2장 > 그 전 4일 1장이지만 7일 전보다 앞에는 없다 → 몰아서(오늘 2장 = 전체의 2/3)
        final c = days({0: 2, 4: 1});
        expect(
          insightPhrases['rising']!.map((p) => p.text.replaceAll('{n}', '2')),
          isNot(contains(tagInsight('뜨개질', c, _now))),
        );
      });

      test('다시 늘어남: 최근 3일 합 > 그 전 4일 합 (잠잠보다 아래, 몰아서보다 위)', () {
        final c = days({0: 3, 1: 1, 4: 1, 10: 3});
        expectFrom('rising', tagInsight('뜨개질', c, _now), [
          '요즘 다시 빠지는 중이에요',
          '잊은 줄 알았는데, 다시 돌아왔네요!',
          '최근 며칠 새 4장이나 모았어요. 진심이네요!',
        ]);
      });

      test('몰아서: 하루가 전체의 절반 이상(2장 이상)', () {
        final c = days({2: 1, 5: 1, 8: 4});
        expectFrom('burst', tagInsight('뜨개질', c, _now), [
          '10월 18일 하루에 4장을 몰아서 캡처했어요',
          '10월 18일, 무슨 일 있었어요? 하루에 4장이나!',
        ]);
      });

      test('오늘 캡처함 → 그 외 순서', () {
        final today = days({0: 1, 3: 1, 4: 1, 6: 1, 9: 1});
        expectFrom('today', tagInsight('뜨개질', today, _now), [
          '오늘도 캡처했어요. 한창 빠져 있는 중!',
          '오늘의 관심사도 #뜨개질',
        ]);
        final steady = days({1: 1, 3: 1, 4: 1, 6: 1, 9: 1});
        expectFrom('steady', tagInsight('뜨개질', steady, _now), [
          '2주 동안 꾸준히 모았어요',
          '2주 중 5일이나 캡처했어요. 진심이네요',
        ]);
      });

      test('pick번째 문구를 고르고, avoid와 같은 문구는 빼고 고른다. 기간 안에 없으면 null', () {
        final c = days({2: 1, 5: 1, 8: 4}); // 몰아서: 문구 2개
        const first = '10월 18일 하루에 4장을 몰아서 캡처했어요';
        const second = '10월 18일, 무슨 일 있었어요? 하루에 4장이나!';
        expect(tagInsight('뜨개질', c, _now, pick: 0)?.text, first);
        expect(tagInsight('뜨개질', c, _now, pick: 1)?.text, second);
        expect(
          tagInsight('뜨개질', c, _now, pick: 2)?.text,
          first,
          reason: '나머지 연산',
        );
        for (final pick in [0, 1, 2, 3]) {
          expect(
            tagInsight('뜨개질', c, _now, pick: pick, avoid: ('burst', 0))?.text,
            second,
          );
        }
        expect(tagInsight('뜨개질', List.filled(14, 0), _now), isNull);
      });

      test('직전 문구는 상황 + 번호로 비교: 날이 지나 숫자가 달라져도 같은 틀은 연달아 안 나온다', () {
        final seen = tagInsight('뜨개질', days({9: 2, 7: 1}), _now, pick: 0)!;
        expect(seen.text, '10월 17일엔 푹 빠져 있었는데, 요즘 7일째 조용하네요');
        final nextDay = tagInsight(
          '뜨개질',
          days({10: 2, 8: 1}),
          _now.add(const Duration(days: 1)),
          pick: 0,
          avoid: seen.id,
        );
        expect(nextDay?.id, ('quiet', 1));
        // 상황이 다르면 번호가 같아도 피할 이유가 없다
        expect(
          tagInsight(
            '뜨개질',
            days({9: 2, 7: 1}),
            _now,
            pick: 0,
            avoid: ('steady', 0),
          )?.text,
          seen.text,
        );
      });
    });

    test('마지막 캡처 문구: 오늘·어제·N일 전 (시각이 아니라 날짜로)', () {
      expect(lastSeenLabel(DateTime(2026, 10, 26, 0, 1), _now), '오늘 마지막');
      expect(
        lastSeenLabel(
          DateTime(2026, 10, 25, 23, 59),
          DateTime(2026, 10, 26, 0, 1),
        ),
        '어제 마지막',
      );
      expect(lastSeenLabel(DateTime(2026, 10, 23, 13), _now), '3일 전 마지막');
    });

    testWidgets('막대는 처음에 올라오고, 애니메이션 줄이기면 바로 다 그려진다', (tester) async {
      double barHeight() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(DailyBars),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration! as BoxDecoration).color ==
                            AppColors.celadon,
                  ),
                )
                .first,
          )
          .height;

      await tester.pumpWidget(_scoped(const TagScreen(tag: '뜨개질')));
      await tester.pump(); // 목록 로드
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeight(), 0, reason: '화면이 다 보일 때까지(390ms) 기다린다');
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeight(), allOf(greaterThan(0), lessThan(AppTagBars.height)));
      await tester.pumpAndSettle();
      expect(barHeight(), AppTagBars.height, reason: '최댓값인 날이 높이를 꽉 채운다');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _scoped(const TagScreen(tag: '뜨개질'), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump();
      final settled = barHeight();
      await tester.pumpAndSettle();
      expect(barHeight(), settled);
    });

    testWidgets('해석 문장은 들어올 때 한 번 정하고, 리빌드·새로고침에도 그대로, 다시 들어오면 직전과 다른 문장', (
      tester,
    ) async {
      // 뜨개질 시드는 "그 외"(문구 2개)
      const steady = ['2주 동안 꾸준히 모았어요', '2주 중 4일이나 캡처했어요. 진심이네요'];
      String shown() =>
          steady.singleWhere((t) => find.text(t).evaluate().isNotEmpty);

      final store = RemineStore(
        FakeScreenshotRepository(now: () => _now, seed: _seed),
        now: () => _now,
      );
      Widget screen(Key key) => RemineScope(
        store: store,
        child: MaterialApp(
          home: TagScreen(key: key, tag: '뜨개질', random: Random(7)),
        ),
      );

      await tester.pumpWidget(screen(const ValueKey(1)));
      await tester.pumpAndSettle();
      final first = shown();

      store.refresh(); // 목록 다시 불러오기
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(shown(), first);

      // 같은 시드로 다시 들어와도(새 화면) 직전 문장은 피한다
      await tester.pumpWidget(screen(const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(shown(), isNot(first));
    });

    testWidgets('캡처를 누르면 상세가 열리고 좌우 넘기기는 이 목록(최근 → 그 전) 안에서만', (tester) async {
      await tester.pumpWidget(_scoped(const TagScreen(tag: '뜨개질')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('tile-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tile-7')));
      await tester.pumpAndSettle();

      final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
      expect(detail.items.map((s) => s.id), [1, 2, 3, 9, 7, 8]);
      expect(detail.initialIndex, 4);
    });
  });

  group('관심사 목록 → 태그 화면 페이드 스루', () {
    double opacityOf(WidgetTester tester, Finder of) => tester
        .widget<Opacity>(
          find.ancestor(of: of, matching: find.byType(Opacity)).first,
        )
        .opacity;

    Future<void> openList(WidgetTester tester, {bool reduce = false}) async {
      await tester.pumpWidget(
        _scoped(
          const InterestsScreen(),
          reduceMotion: reduce,
          // 카드 하나: 두 카드가 같은 캡처를 보이면 Hero 태그가 겹친다(전환과 별개).
          seed: [
            for (var i = 1; i <= 4; i++)
              _shot(i, i, Category.shopping, ['뜨개질']),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();
    }

    testWidgets('목록이 먼저 빠지고 태그 화면이 뒤이어, 돌아올 땐 반대로', (tester) async {
      await openList(tester);
      await tester.tap(find.byType(InterestCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final list = find.byType(InterestCard).first;
      expect(opacityOf(tester, list), allOf(greaterThan(0), lessThan(1)));
      expect(opacityOf(tester, find.byType(TagScreen)), 0, reason: '180ms 전');

      await tester.pump(const Duration(milliseconds: 150)); // 250ms
      expect(opacityOf(tester, list), 0, reason: '225ms에 다 빠진다');
      expect(opacityOf(tester, find.byType(TagScreen)), greaterThan(0));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, find.byType(TagScreen)), 1);

      // 뒤로 버튼·시스템 뒤로(스와이프)는 둘 다 pop이다.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, find.byType(TagScreen)), lessThan(1));
      expect(
        opacityOf(tester, find.byType(InterestCard).first),
        0,
        reason: '180ms 전',
      );
      await tester.pump(const Duration(milliseconds: 150)); // 250ms
      expect(opacityOf(tester, find.byType(TagScreen)), 0);
      await tester.pumpAndSettle();
      expect(find.byType(TagScreen), findsNothing);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.byType(InterestCard).first,
                matching: find.byType(Opacity),
              ),
            )
            .every((o) => o.opacity == 1),
        isTrue,
        reason: '끝나면 목록은 원래대로',
      );
    });

    testWidgets('heroes: false면 들어갈 때·돌아올 때 Hero가 날지 않고, 다 들어온 뒤에는 그대로', (
      tester,
    ) async {
      // 같은 tag의 Hero: 첫 화면은 왼쪽 위, 새 화면은 오른쪽 아래. 날면 중간 위치에 보인다.
      Widget page(Alignment at) => Scaffold(
        body: Align(
          alignment: at,
          child: const Hero(
            tag: 'h',
            child: SizedBox(width: 40, height: 40, child: Text('H')),
          ),
        ),
      );
      bool flying() => tester
          .widgetList<Text>(find.text('H'))
          .indexed
          .map((e) => tester.getCenter(find.text('H').at(e.$1)))
          .any((c) => c.dy > 100 && c.dy < 500); // 끝점(위·아래)이 아닌 곳

      for (final heroes in [true, false]) {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, home: page(Alignment.topLeft)),
        );
        nav.currentState!.push(
          fadeThroughRoute(
            nav.currentContext!,
            (_) => page(Alignment.bottomRight),
            heroes: heroes,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(flying(), heroes, reason: 'push, heroes=$heroes');
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<HeroMode>(find.byType(HeroMode))
              .every((m) => m.enabled),
          isTrue,
          reason: '다 들어온 뒤에는 이 화면에서 상세로 가는 Hero가 난다',
        );
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(flying(), heroes, reason: 'pop, heroes=$heroes');
        await tester.pumpAndSettle();
      }
    });

    testWidgets('애니메이션 줄이기면 즉시 바뀐다', (tester) async {
      await openList(tester, reduce: true);
      await tester.tap(find.byType(InterestCard).first);
      await tester.pump();
      await tester.pump();
      expect(opacityOf(tester, find.byType(TagScreen)), 1);
    });
  });

  group('관심사 탭 머릿속 지도', () {
    testWidgets('탭에 들어올 때마다 지도부터, 다 그려져도 저절로 넘어가지 않고 [목록 보기]로 목록', (
      tester,
    ) async {
      await tester.pumpWidget(_scoped(const InterestsScreen(active: false)));
      await tester.pumpAndSettle();
      expect(
        find.byType(InterestBrainMap),
        findsNothing,
        reason: '숨은 탭에서는 시작하지 않는다',
      );

      await tester.pumpWidget(_scoped(const InterestsScreen(active: true)));
      await tester.pump();
      expect(find.byType(InterestBrainMap), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.byType(InterestBrainMap),
        findsOneWidget,
        reason: '끝나도 지도 그대로',
      );
      expect(find.byType(InterestCard), findsNothing);

      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();
      expect(find.byType(InterestBrainMap), findsNothing);
      expect(find.byType(InterestCard), findsWidgets);

      await tester.pumpWidget(_scoped(const InterestsScreen(active: false)));
      await tester.pumpWidget(_scoped(const InterestsScreen(active: true)));
      await tester.pump();
      expect(
        find.byType(InterestBrainMap),
        findsOneWidget,
        reason: '다시 들어오면 또 지도부터',
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(InterestBrainMap),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as BrainPainter;
      expect(painter.t, lessThan(0.1), reason: '처음부터 다시 그린다');
    });

    testWidgets('그리는 중에도 아무 데나 누르면 목록', (tester) async {
      await tester.pumpWidget(_scoped(const InterestsScreen()));
      await tester.pump();
      expect(find.byType(InterestBrainMap), findsOneWidget);

      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      expect(find.byType(InterestBrainMap), findsNothing);
      expect(find.byType(InterestCard), findsWidgets);
    });

    testWidgets('애니메이션 줄이기면 완성된 지도를 바로 보여 주고 버튼으로 넘어간다', (tester) async {
      await tester.pumpWidget(
        _scoped(const InterestsScreen(), reduceMotion: true),
      );
      await tester.pump();

      expect(find.byType(InterestBrainMap), findsOneWidget);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(InterestBrainMap),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as BrainPainter;
      expect(painter.t, 1.0);

      await tester.tap(find.text('목록 보기'));
      await tester.pump();
      expect(find.byType(InterestCard), findsWidgets);
    });

    testWidgets('관심사가 없으면 지도 없이 빈 상태', (tester) async {
      await tester.pumpWidget(
        _scoped(
          const InterestsScreen(),
          seed: [
            _shot(1, 1, Category.etc, ['하나']),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(InterestBrainMap), findsNothing);
      expect(find.text('아직 반복해서 캡처한 게 없어요'), findsOneWidget);
    });

    test('원 배치: 많이 캡처할수록 크고, 7일 이상 지난 관심사는 잊은 것, 연결은 같은 캡처를 공유한 관심사', () async {
      final interests = await FakeScreenshotRepository(
        now: () => _now,
        seed: _seed,
      ).interests();
      final nodes = layoutNodes(interests);

      // 횟수 많은 순(동점은 이름순): 뜨개질 4 → 가방 3 → 도안 3
      expect(nodes.map((n) => n.interest.tag), ['뜨개질', '가방', '도안']);
      expect(nodes[0].radius, greaterThan(nodes[1].radius));
      expect(nodes.map((n) => n.interest.forgotten), [false, true, false]);
      expect(nodes[0].interest.linkedTags, ['도안']);
      expect(nodes[1].interest.linkedTags, isEmpty);
    });

    test('서버 응답의 linkedTags를 읽고, 옛 응답(필드 없음)은 빈 목록', () {
      Interest parse(Map<String, dynamic> extra) => Interest.fromJson({
        'tag': '뜨개질',
        'category': 'SHOPPING',
        'captureCount': 3,
        'dormantDays': 8,
        'recent': <dynamic>[],
        ...extra,
      }, spanDays: 14);

      expect(
        parse({
          'linkedTags': ['도안'],
        }).linkedTags,
        ['도안'],
      );
      expect(parse({}).linkedTags, isEmpty);
      expect(parse({}).forgotten, isTrue);
    });
  });
}
