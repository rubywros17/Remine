import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      rig.status.advance(7);
      rig.status.finish();
      await tester.pump();
      expect(
        find.text('홈으로'),
        findsOneWidget,
        reason: '보는 중에 끝나면 그 자리에서 완료 상태',
      );
      await tester.ensureVisible(find.text('홈으로'));
      await tester.tap(find.text('홈으로'));
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
      await tester.pump(const Duration(milliseconds: 16));
      expect(barHeight(), lessThan(AppTagBars.height));
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
