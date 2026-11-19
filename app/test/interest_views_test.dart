import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remine/core/helpers.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/detail_screen.dart';
import 'package:remine/screens/interests_screen.dart';
import 'package:remine/screens/older_range_screen.dart';
import 'package:remine/screens/older_shots_screen.dart';
import 'package:remine/screens/older_texts.dart';
import 'package:remine/screens/tag_screen.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/interest_brain_map.dart';
import 'package:remine/widgets/sync_banner.dart';

import 'support/fake_device.dart';
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

/// 뜨개질: 10월 5장(쇼핑·정보·문화생활) + 9월 1장. 뜨개질·도안이 캡처 1~3을 공유한다.
/// 가방은 마지막 캡처가 39일 전(30일 넘음)이라 "잊고 있었던 관심사".
final _seed = [
  _shot(1, 1, Category.shopping, ['뜨개질', '도안']),
  _shot(2, 2, Category.info, ['뜨개질', '도안']),
  _shot(3, 3, Category.shopping, ['뜨개질', '도안']),
  _shot(9, 4, Category.info, ['뜨개질']),
  _shot(4, 39, Category.shopping, ['가방']),
  _shot(5, 40, Category.shopping, ['가방']),
  _shot(6, 41, Category.shopping, ['가방']),
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
    testWidgets('카테고리 상관없이 그 태그 캡처 전부, 전체 장수·월별 막대·달별 묶음', (tester) async {
      await tester.pumpWidget(_scoped(const TagScreen(tag: '뜨개질')));
      await tester.pumpAndSettle();

      expect(find.text('#뜨개질'), findsOneWidget);
      expect(find.text('전체 6장 · 어제 마지막'), findsOneWidget);
      expect(find.text('6'), findsOneWidget, reason: '오른쪽 위 큰 숫자 = 전체 장수');
      expect(find.bySemanticsLabel('#뜨개질 전체 6장'), findsOneWidget);
      expect(find.bySemanticsLabel('최근 2개월 중 2개월 캡처'), findsOneWidget);
      expect(find.text('이번 달'), findsOneWidget);
      expect(
        find.text('2026.09'),
        findsNWidgets(2),
        reason: '막대 시작 = 첫 캡처의 달, 그리드 9월 묶음',
      );
      // 1·2·3·4·20일 전 1장씩 → 최근 3일(오늘 포함) 2장 = 그 전 4일 2장, 몰아서·오늘 아님 → 그 외
      expect(
        find.text('한 달 동안 꾸준히 모았어요').evaluate().length +
            find.text('한 달 중 5일이나 캡처했어요. 진심이네요').evaluate().length,
        1,
      );
      expect(find.text('2026.10'), findsOneWidget);
      for (final id in [1, 2, 3, 9, 7, 8]) {
        expect(
          find.byKey(ValueKey('tile-$id')),
          findsOneWidget,
          reason: '캡처 $id',
        );
      }
      expect(find.byKey(const ValueKey('tile-4')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('tile-7')));
      // 10월 묶음(1·2·3·9·7)이 9월 묶음(8)보다 위에 있다
      await tester.ensureVisible(find.byKey(const ValueKey('tile-8')));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('tile-3'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('tile-8'))).dy),
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

      test('잊고 있었던 관심사(서버 status)면 패턴과 상관없이 오래 잠잠', () {
        final c = days({9: 3, 7: 1});
        expectFrom('dormant', tagInsight('뜨개질', c, _now, forgotten: true), [
          '마지막 캡처가 7일 전이에요. 다시 꺼내 볼까요?',
          '한 달 넘게 소식이 없어요. 아직 좋아하죠?',
        ]);
        expect(tagInsight('뜨개질', c, _now)?.id.$1, isNot('dormant'));
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
            '한 달 동안 꾸준히 모았어요',
            '한 달 중 3일이나 캡처했어요. 진심이네요',
          });
        });

        test('3일 이상 + 가장 많던 날 2장: 가장 많던 날 문구도 나온다', () {
          expect(lines(days({4: 1, 6: 2, 9: 1, 10: 1, 11: 1})), {
            '한 달 동안 꾸준히 모았어요',
            '한 달 중 5일이나 캡처했어요. 진심이네요',
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

      test('마지막 캡처로부터 지난 날짜 경계: 2·3·13·14일, 기간 밖이어도 요즘 것이면 기본 문구', () {
        String? at(int daysAgo) => tagInsight(
          '뜨개질',
          days({daysAgo: 1}),
          _now,
          lastCapture: _now.subtract(Duration(days: daysAgo)),
        )?.id.$1;

        expect(at(2), 'new', reason: '최근 3일에만 있음');
        expect(at(3), 'steady', reason: '최근 3일 밖이라 새로 생김이 아니다');
        expect(at(13), 'steady');
        expect(at(14), 'steady', reason: '기간 밖(0장)이지만 서버가 요즘 것이라 했다');
      });

      test('오래 잠잠: 기간 안 0장이면 전체 목록의 마지막 캡처 기준, 그것도 없으면 null', () {
        expectFrom(
          'dormant',
          tagInsight(
            '뜨개질',
            List.filled(14, 0),
            _now,
            forgotten: true,
            lastCapture: DateTime(2026, 9, 6, 23),
          ),
          ['마지막 캡처가 50일 전이에요. 다시 꺼내 볼까요?', '한 달 넘게 소식이 없어요. 아직 좋아하죠?'],
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
          '한 달 동안 꾸준히 모았어요',
          '한 달 중 5일이나 캡처했어요. 진심이네요',
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
        final seen = tagInsight(
          '뜨개질',
          days({2: 1, 5: 1, 8: 4}),
          _now,
          pick: 0,
        )!;
        expect(seen.text, '10월 18일 하루에 4장을 몰아서 캡처했어요');
        final nextDay = tagInsight(
          '뜨개질',
          days({3: 1, 6: 1, 9: 4}),
          _now.add(const Duration(days: 1)),
          pick: 0,
          avoid: seen.id,
        );
        expect(nextDay?.id, ('burst', 1));
        // 상황이 다르면 번호가 같아도 피할 이유가 없다
        expect(
          tagInsight(
            '뜨개질',
            days({2: 1, 5: 1, 8: 4}),
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
                  of: find.byType(MonthlyBars),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration! as BoxDecoration).color ==
                            AppColors.celadon,
                  ),
                )
                .last, // 이번 달(가장 많은 달)
          )
          .height;

      await tester.pumpWidget(_scoped(const TagScreen(tag: '뜨개질')));
      await tester.pump(); // 목록 로드
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeight(), 0, reason: '화면이 다 보일 때까지(390ms) 기다린다');
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeight(), allOf(greaterThan(0), lessThan(AppTagBars.height)));
      await tester.pumpAndSettle();
      expect(barHeight(), AppTagBars.height, reason: '최댓값인 달이 높이를 꽉 채운다');

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
      const steady = ['한 달 동안 꾸준히 모았어요', '한 달 중 5일이나 캡처했어요. 진심이네요'];
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

    testWidgets('캡처를 누르면 상세가 열리고 좌우 넘기기는 이 목록(최신순, 달 묶음 순서 그대로) 안에서만', (
      tester,
    ) async {
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
    setUp(InterestBrainMap.resetIntro);

    BrainPainter painterOf(WidgetTester tester) => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(InterestBrainMap),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((c) => c.painter)
        .whereType<BrainPainter>()
        .single;

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
      expect(find.byType(InterestBrainMap), findsOneWidget);
      expect(
        find.byType(InterestCard),
        findsNothing,
        reason: '첫 프레임부터 지도만(목록이 비치지 않는다)',
      );
      expect(painterOf(tester).intro, isTrue, reason: '첫 진입은 얼굴부터');

      await tester.pump(const Duration(seconds: 8));
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
      final again = painterOf(tester);
      expect(again.intro, isFalse, reason: '두 번째부터는 얼굴·확대 없이');
      expect(
        again.ms,
        closeTo(AppBrain.brainStart, 20),
        reason: '뇌 그리기부터 다시 그린다',
      );
    });

    testWidgets('그리는 중에 누르면 바로 마지막 상태, 다 그려진 뒤 누르면 목록', (tester) async {
      await tester.pumpWidget(_scoped(const InterestsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(painterOf(tester).ms, lessThan(AppBrain.brainStart));

      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(
        find.byType(InterestBrainMap),
        findsOneWidget,
        reason: '목록으로 가지 않는다',
      );
      final p = painterOf(tester);
      expect(
        p.ms,
        brainTotalMs(
          p.chips.length,
          brainLinks([for (final c in p.chips) c.node]).length,
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);

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
      final p = painterOf(tester);
      expect(
        p.ms,
        brainTotalMs(
          p.chips.length,
          brainLinks([for (final c in p.chips) c.node]).length,
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);

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

    test('순서: 잊고 있었던 관심사(30일 넘음) 먼저, 그다음 많이 캡처한 순, 연결은 같은 카테고리 실선', () async {
      final interests = await FakeScreenshotRepository(
        now: () => _now,
        seed: _seed,
      ).interests();
      final nodes = layoutNodes(interests);

      // 잊은 가방 3 → 요즘 것 횟수 많은 순: 뜨개질 6 → 도안 3
      expect(nodes.map((n) => n.interest.tag), ['가방', '뜨개질', '도안']);
      // 셋 다 쇼핑 → 같은 카테고리 실선 2개(가까운 자리부터). 뜨개질-도안 같은 캡처는 이미 실선 줄로 이어져 점선 없음.
      expect(brainLinks(nodes).map((l) => l.kind), [
        BrainLinkKind.solid,
        BrainLinkKind.solid,
      ]);
      expect(nodes.map((n) => n.interest.forgotten), [true, false, false]);
      expect(nodes[1].interest.linkedTags, ['도안']);
      expect(nodes[0].interest.linkedTags, isEmpty);
    });

    Interest interest(
      String tag,
      int count, {
      int dormant = 0,
      Category category = Category.etc,
      List<String> linked = const [],
    }) => Interest(
      tag: tag,
      category: category,
      forgotten: dormant > Interest.defaultRecentDays,
      captureCount: count,
      dormantDays: dormant,
      peakMonth: 10,
      peakMonthCount: count,
      latestMonth: 10,
      latestMonthCount: count,
      recent: const [],
      linkedTags: linked,
    );

    final longSeven = [
      interest('겨울캠핑장비추천리스트총정리', 9),
      interest('니트가디건코디', 8),
      interest('제주도한달살기숙소', 7, dormant: 39),
      interest('홈카페레시피', 6),
      interest('아이폰케이스', 5),
      interest('주말브런치맛집', 4, dormant: 38),
      interest('전시회일정정리', 3),
    ];

    for (final (name, size, scale) in [
      ('360×800', const Size(320, 470), 1.0),
      ('360×640', const Size(320, 320), 1.0),
      ('360×800 글자 1.3배', const Size(320, 470), 1.3),
    ]) {
      test('칩: 긴 키워드도 서로 10px 이상 떨어지고 캔버스 안 · $name', () {
        final chips = layoutChips(
          layoutNodes(longSeven),
          size,
          TextScaler.linear(scale),
        );
        expect(chips, isNotEmpty);
        final canvas = Offset.zero & size;
        for (final (i, a) in chips.indexed) {
          expect(
            canvas.inflate(0.5).contains(a.rect.topLeft) &&
                canvas.inflate(0.5).contains(a.rect.bottomRight),
            isTrue,
            reason: '${a.node.interest.tag} ${a.rect} 캔버스 $canvas',
          );
          for (final b in chips.skip(i + 1)) {
            expect(
              a.rect.inflate(4.9).overlaps(b.rect.inflate(4.9)),
              isFalse,
              reason: '${a.node.interest.tag} ↔ ${b.node.interest.tag}',
            );
          }
        }
      });
    }

    test('칩: # 없이 키워드만, 1위·잊은 관심사는 레몬, 나머지는 연셀라돈', () {
      // 긴 키워드 7개가 다 앉도록 넓은 캔버스(태블릿 가로).
      final chips = layoutChips(
        layoutNodes(longSeven),
        const Size(1000, 700),
        TextScaler.noScaling,
      );
      // 잊은 것(제주도·주말)이 먼저 뽑히고 요즘 것과 번갈아 앉는다.
      expect(chips.map((c) => c.node.interest.tag), [
        '제주도한달살기숙소',
        '겨울캠핑장비추천리스트총정리',
        '주말브런치맛집',
        '니트가디건코디',
        '홈카페레시피',
        '아이폰케이스',
        '전시회일정정리',
      ]);
      expect(chips.map((c) => c.color), [
        AppBrain.chipTop, // 1위(잊은 관심사 1등)
        AppBrain.chip,
        AppBrain.chipTop, // 잊은 관심사
        AppBrain.chip,
        AppBrain.chip,
        AppBrain.chip,
        AppBrain.chip,
      ]);
      expect(chips.first.rect.height, greaterThan(chips[1].rect.height));
    });

    group('키워드 고르기: 잊은 4 + 요즘 3', () {
      List<Interest> many(String p, int n, {bool forgotten = false}) => [
        for (var i = 0; i < n; i++)
          interest('$p$i', 20 - i, dormant: forgotten ? 40 : 0),
      ];
      List<String> tags(List<Interest> l) => [for (final i in l) i.tag];

      test('잊은 6 · 요즘 5 → 잊은 4 + 요즘 3, 1등은 잊은 1등, 그 뒤 번갈아', () {
        final picked = pickBrainInterests([
          ...many('잊', 6, forgotten: true),
          ...many('요', 5),
        ]);
        expect(tags(picked), ['잊0', '요0', '잊1', '요1', '잊2', '요2', '잊3']);
      });

      test('요즘 1개 → 잊은 6 + 요즘 1', () {
        final picked = pickBrainInterests([
          ...many('잊', 9, forgotten: true),
          ...many('요', 1),
        ]);
        expect(tags(picked), ['잊0', '요0', '잊1', '잊2', '잊3', '잊4', '잊5']);
      });

      test('잊은 0개 → 요즘 7', () {
        expect(tags(pickBrainInterests(many('요', 9))), [
          '요0',
          '요1',
          '요2',
          '요3',
          '요4',
          '요5',
          '요6',
        ]);
      });

      test('빈 목록 → 빈 지도', () {
        expect(pickBrainInterests(const []), isEmpty);
        expect(layoutNodes(const []), isEmpty);
      });
    });

    group('연결선: 같은 카테고리 실선 · 같은 캡처 점선', () {
      test('같은 카테고리 4개 → 실선 3개, 가까운 자리끼리 한 줄', () {
        final nodes = layoutNodes([
          for (var i = 0; i < 4; i++)
            interest('쇼$i', 10 - i, category: Category.shopping),
        ]);
        final links = brainLinks(nodes);
        expect(links, hasLength(3));
        expect(links.every((l) => l.kind == BrainLinkKind.solid), isTrue);
        // 4개가 모두 이어진다(신장 트리).
        final reached = {0};
        for (var k = 0; k < 3; k++) {
          for (final l in links) {
            if (reached.contains(l.a) || reached.contains(l.b)) {
              reached.addAll([l.a, l.b]);
            }
          }
        }
        expect(reached, {0, 1, 2, 3});
        // 가장 짧은 후보부터: 전체 길이가 모든 신장 트리 중 최소(4개라 전부 따져 본다).
        double len(Iterable<(int, int)> es) => es.fold(
          0,
          (s, e) => s + (nodes[e.$1].slot - nodes[e.$2].slot).distance,
        );
        final all = [
          for (var a = 0; a < 4; a++)
            for (var b = a + 1; b < 4; b++) (a, b),
        ];
        var best = double.infinity;
        for (var x = 0; x < all.length; x++) {
          for (var y = x + 1; y < all.length; y++) {
            for (var z = y + 1; z < all.length; z++) {
              final es = [all[x], all[y], all[z]];
              final seen = {0};
              for (var k = 0; k < 3; k++) {
                for (final e in es) {
                  if (seen.contains(e.$1) || seen.contains(e.$2)) {
                    seen.addAll([e.$1, e.$2]);
                  }
                }
              }
              if (seen.length == 4) best = min(best, len(es));
            }
          }
        }
        expect(len([for (final l in links) (l.a, l.b)]), closeTo(best, 0.001));
      });

      test('다른 카테고리 linkedTags → 점선, 같은 카테고리이면서 linkedTags → 실선 하나만', () {
        final nodes = layoutNodes([
          interest('가', 9, category: Category.shopping, linked: ['나', '다']),
          interest('나', 8, category: Category.shopping, linked: ['가']),
          interest('다', 7, category: Category.info, linked: ['가']),
        ]);
        expect(brainLinks(nodes).map((l) => (l.a, l.b, l.kind)), [
          (0, 1, BrainLinkKind.solid), // 가-나: 같은 카테고리 + 같은 캡처 → 실선 하나
          (0, 2, BrainLinkKind.dashed), // 가-다: 같은 캡처만 → 점선
        ]);
      });

      test('외톨이 칩(실선·점선 없음) → 가장 가까운 이어진 칩에 연한 선 하나, 맨 뒤', () {
        final nodes = layoutNodes([
          interest('가', 9, category: Category.shopping),
          interest('나', 8, category: Category.shopping),
          interest('다', 7, category: Category.info),
        ]);
        final links = brainLinks(nodes);
        expect(links.map((l) => l.kind), [
          BrainLinkKind.solid,
          BrainLinkKind.faint,
        ]);
        final faint = links.last;
        expect([faint.a, faint.b], contains(2));
        final other = nodes[faint.a == 2 ? faint.b : faint.a];
        for (final n in nodes.take(2)) {
          expect(
            (other.slot - nodes[2].slot).distance,
            lessThanOrEqualTo((n.slot - nodes[2].slot).distance),
          );
        }
      });

      test('모두 외톨이면 순위 순으로 앞 칩 중 가까운 칩에(n-1개)', () {
        final nodes = layoutNodes([
          interest('가', 9, category: Category.shopping),
          interest('나', 8, category: Category.info),
          interest('다', 7, category: Category.place),
        ]);
        expect(brainLinks(nodes).map((l) => l.kind), [
          BrainLinkKind.faint,
          BrainLinkKind.faint,
        ]);
      });

      test('칩 위치가 있으면 다른 칩 뒤를 지나가는 실선은 피한다', () {
        // 가·나·다가 한 줄로 서 있고 셋 다 같은 카테고리: 가-다는 나 뒤를 지나므로 가-나-다로 잇는다.
        final nodes = layoutNodes([
          interest('가', 9, category: Category.shopping),
          interest('나', 8, category: Category.shopping),
          interest('다', 7, category: Category.shopping),
        ]);
        final rects = {
          0: const Rect.fromLTWH(0, 0, 40, 20),
          1: const Rect.fromLTWH(100, 0, 40, 20),
          2: const Rect.fromLTWH(200, 0, 40, 20),
        };
        final links = brainLinks(nodes, rects: rects);
        expect(links.map((l) => (l.a, l.b)), [(0, 1), (1, 2)]);
        for (final l in links) {
          expect(brainLinkCrossings(l, rects), isEmpty);
        }
      });
    });

    group('배치(자리는 고정 육각형, 누가 어디 앉는지만 계산)', () {
      // 둘레 자리 0~5는 원형으로 이웃(5 다음 0).
      bool neighbors(int a, int b) => (a - b).abs() == 1 || (a - b).abs() == 5;

      test('같은 카테고리 두 칩은 이웃 자리', () {
        final nodes = layoutNodes([
          interest('가', 9, dormant: 40),
          interest('나', 8, category: Category.shopping),
          interest('다', 7, dormant: 40, category: Category.info),
          interest('라', 6, category: Category.place),
          interest('마', 5, dormant: 40, category: Category.shopping),
          interest('바', 4, category: Category.chat),
          interest('사', 3, dormant: 40, category: Category.schedule),
        ]);
        final shop = nodes
            .where((n) => n.interest.category == Category.shopping)
            .toList();
        expect(neighbors(shop[0].seat, shop[1].seat), isTrue);
      });

      test('같은 데이터면 항상 같은 배치', () {
        List<int> seats() => [for (final n in layoutNodes(longSeven)) n.seat];
        expect(seats(), seats());
      });

      test('1등은 가운데, 나머지 6개는 둘레 6자리에 하나씩(위 2 · 양옆 2 · 아래 2)', () {
        final nodes = layoutNodes(longSeven);
        expect(nodes.first.seat, -1);
        expect(nodes.skip(1).map((n) => n.seat).toSet(), {0, 1, 2, 3, 4, 5});
        expect(nodes.where((n) => n.slot.dy < -0.1), hasLength(2));
        expect(nodes.where((n) => n.slot.dy > 0.1), hasLength(2));
      });

      test('긴 키워드는 좌우 끝 자리보다 위·아래 자리', () {
        final ring = layoutNodes(longSeven).skip(1).toList()
          ..sort(
            (a, b) => b.interest.tag.length.compareTo(a.interest.tag.length),
          );
        // 가장 긴 4개는 위·아래(1·2·4·5), 가장 짧은 2개가 좌우 끝(0·3).
        expect(
          ring.take(4).map((n) => n.seat),
          everyElement(isNot(anyOf(0, 3))),
        );
      });
    });

    group('연결선 색', () {
      test('실선 = 카테고리 색(서랍 점과 같은 토큰)을 흰색 쪽 30% · 95%, 두께 그대로', () {
        for (final c in Category.values) {
          final paint = brainLinkPaint((
            a: 0,
            b: 1,
            kind: BrainLinkKind.solid,
          ), c);
          final want = Color.lerp(AppCategoryColors.of(c), Colors.white, 0.3)!;
          expect(paint.color.r, closeTo(want.r, 0.001), reason: '$c');
          expect(paint.color.g, closeTo(want.g, 0.001), reason: '$c');
          expect(paint.color.b, closeTo(want.b, 0.001), reason: '$c');
          expect(paint.color.a, closeTo(0.95, 0.01), reason: '$c');
          expect(paint.strokeWidth, closeTo(AppBrain.linkStroke, 0.001));
        }
      });

      test('점선 = 흰색 55%, 두께 1.5, 대시 4/4', () {
        final paint = brainLinkPaint((
          a: 0,
          b: 1,
          kind: BrainLinkKind.dashed,
        ), Category.shopping);
        expect(paint.color.r, 1);
        expect(paint.color.g, 1);
        expect(paint.color.b, 1);
        expect(paint.color.a, closeTo(0.55, 0.01));
        expect(paint.strokeWidth, 1.5);
        expect((AppBrain.linkDash, AppBrain.linkDashGap), (4.0, 4.0));
      });

      test('연한 선 = 흰색 45%, 두께는 실선과 같다', () {
        final paint = brainLinkPaint((
          a: 0,
          b: 1,
          kind: BrainLinkKind.faint,
        ), Category.shopping);
        expect(paint.color.r, 1);
        expect(paint.color.a, closeTo(0.45, 0.01));
        expect(paint.strokeWidth, closeTo(AppBrain.linkStroke, 0.001));
      });

      test('디버그 요약: 실선 카테고리별 · 점선 · 같은 캡처 쌍(같은 카테고리 생략)', () {
        final nodes = layoutNodes([
          interest('가', 9, category: Category.shopping, linked: ['나', '다']),
          interest('나', 8, category: Category.shopping, linked: ['가']),
          interest('다', 7, category: Category.info, linked: ['가']),
          interest('라', 6, category: Category.info),
        ]);
        final lines = brainLinkSummary(nodes).split('\n');
        expect(
          lines.first,
          '[brain] 실선 2(${Category.shopping.label} 1, ${Category.info.label} 1)'
          ' · 점선 1 · 같은 캡처 쌍 2(같은 카테고리라 생략 1) · 연한 선 0',
        );
        // 선마다 한 줄: (a, b, 종류, 색, 두 칩 카테고리)
        expect(lines.skip(1), hasLength(3));
        expect(lines[1], startsWith('[brain]   (가, 나, solid, #'));
        expect(
          lines[1],
          endsWith('${Category.shopping.label}/${Category.shopping.label})'),
        );
      });
    });

    test('서버 응답의 linkedTags·status를 읽고, 옛 응답(linkedTags 없음)은 빈 목록', () {
      Interest parse(Map<String, dynamic> extra) => Interest.fromJson({
        'tag': '뜨개질',
        'category': 'SHOPPING',
        'status': 'FORGOTTEN',
        'captureCount': 3,
        'dormantDays': 8,
        'peakMonth': 9,
        'peakMonthCount': 3,
        'latestMonth': 9,
        'latestMonthCount': 3,
        'recent': <dynamic>[],
        ...extra,
      });

      expect(
        parse({
          'linkedTags': ['도안'],
        }).linkedTags,
        ['도안'],
      );
      expect(parse({}).linkedTags, isEmpty);
      expect(parse({}).forgotten, isTrue, reason: '일수로 다시 재지 않고 서버 status를 쓴다');
      expect(parse({'status': 'RECENT'}).forgotten, isFalse);
    });
  });

  group('관심사 목록 맨 아래 "더 오래된 관심사도 찾아볼까요?"', () {
    /// 하루 1장씩 [days]일 치 갤러리.
    FakeGalleryReader gallery(int days) => FakeGalleryReader(
      photos: [
        for (var d = 0; d < days; d++)
          GalleryPhoto(
            id: 'g$d',
            fileName: 'Screenshot_$d.png',
            takenAt: _now.subtract(Duration(days: d)),
            modifiedAt: d,
          ),
      ],
    );

    Future<void> openList(
      WidgetTester tester,
      FakeGalleryReader reader,
      InMemorySettingsStore settings,
    ) async {
      tester.view.physicalSize = const Size(412, 2000); // 목록 끝까지 한 화면에
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _scoped(
          // 앱에서는 탭 화면(Scaffold) 안에 있다(검색창 TextField에 Material이 필요)
          Scaffold(
            body: DeviceScope(
              services: fakeServices(reader, settings: settings),
              child: const InterestsScreen(),
            ),
          ),
          // 카드 하나(두 카드가 같은 캡처를 보이면 다른 화면으로 갈 때 Hero 태그가 겹친다)
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

    testWidgets('아직 안 본 예전 스크린샷이 있으면 목록 끝에 보이고, 범위를 안 골랐으면 범위 고르기로', (
      tester,
    ) async {
      await openList(tester, gallery(500), InMemorySettingsStore(false));

      expect(find.text(OlderTexts.moreTitle), findsOneWidget);
      expect(
        find.text(OlderTexts.moreBody(200)),
        findsOneWidget,
        reason: '최근 300장 뒤 200장',
      );
      // 요즘 모으는 중 섹션 뒤(목록 맨 끝)
      expect(
        tester.getTopLeft(find.text(OlderTexts.moreTitle)).dy,
        greaterThan(tester.getTopLeft(find.text('요즘 모으는 중')).dy),
      );

      await tester.tap(find.text(OlderTexts.moreButton));
      await tester.pumpAndSettle();
      expect(find.byType(OlderRangeScreen), findsOneWidget);
      expect(find.text(OlderTexts.confirm), findsOneWidget, reason: '설정 모드');
    });

    testWidgets('"최근 300장"을 고른 사람에게도 보이고, 범위를 골랐으면 예전 스크린샷 화면으로', (
      tester,
    ) async {
      final settings = InMemorySettingsStore(false)
        ..olderKind = OlderRangeKind.recent300
        ..olderRange = olderRangeNone;
      await openList(tester, gallery(500), settings);

      expect(find.text(OlderTexts.moreTitle), findsOneWidget);
      await tester.tap(find.text(OlderTexts.moreButton));
      await tester.pumpAndSettle();
      expect(find.byType(OlderShotsScreen), findsOneWidget);
    });

    testWidgets('남은 예전 스크린샷이 0이면 숨긴다', (tester) async {
      await openList(tester, gallery(250), InMemorySettingsStore(false));
      expect(find.text(OlderTexts.moreTitle), findsNothing);
    });

    testWidgets('검색 중에는 숨긴다', (tester) async {
      await openList(tester, gallery(500), InMemorySettingsStore(false));
      expect(find.text(OlderTexts.moreTitle), findsOneWidget);

      await tester.tap(find.byTooltip('관심사 검색'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '뜨개');
      await tester.pumpAndSettle();
      expect(find.text(OlderTexts.moreTitle), findsNothing);
    });

    testWidgets('기기 모드가 아니면(크롬 가짜 데이터) 보이지 않는다', (tester) async {
      await tester.pumpWidget(_scoped(const InterestsScreen()));
      await tester.pump();
      await tester.tap(find.text('목록 보기'));
      await tester.pumpAndSettle();
      expect(find.text(OlderTexts.moreTitle), findsNothing);
    });
  });
}
