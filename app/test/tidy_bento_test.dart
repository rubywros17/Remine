import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/data/screenshot_repository.dart';
import 'package:remine/data/tidy_bundles.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/category_summary.dart';
import 'package:remine/models/category_update.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/tidy_bundle_screen.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/peek_preview.dart';
import 'package:remine/widgets/selectable_thumb.dart';
import 'package:remine/widgets/tidy_bento.dart';

import 'support/fake_device.dart';

final _now = DateTime(2026, 10, 21, 12); // 수요일

ScreenshotItem _shot(
  int id,
  int daysAgo, {
  Category category = Category.info,
}) => ScreenshotItem(
  id: id,
  localAssetId: 'a$id',
  takenAt: _now.subtract(Duration(days: daysAgo)),
  category: category,
  tags: const [],
);

/// 묶음 계산이 저장소 전체 목록을 몇 번 읽었는지 센다.
class _CountingRepo implements ScreenshotRepository {
  _CountingRepo(this._base);

  final FakeScreenshotRepository _base;
  int allCalls = 0;

  @override
  Future<List<ScreenshotItem>> all() {
    allCalls++;
    return _base.all();
  }

  @override
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) => _base.list(category: category, tag: tag, page: page, size: size);

  @override
  Future<CategorySummary> summary() => _base.summary();

  @override
  Future<CategoryUpdate> updateCategory(int id, Category category) =>
      _base.updateCategory(id, category);

  @override
  Future<void> trash(int id) => _base.trash(id);

  @override
  Future<void> restore(int id) => _base.restore(id);

  @override
  Future<List<Interest>> interests() => _base.interests();
}

Future<void> _pumpTidy(
  WidgetTester tester, {
  required List<ScreenshotItem> seed,
  FakeGalleryReader? reader,
  ScreenshotRepository Function(FakeScreenshotRepository)? wrap,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final base = FakeScreenshotRepository(now: () => _now, seed: seed);
  await tester.pumpWidget(
    RemineApp(
      repository: wrap?.call(base) ?? base,
      now: () => _now,
      device: fakeServices(
        reader ?? FakeGalleryReader(),
        trash: InMemoryTrashStore(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('정리'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.runAsync(pumpEventQueue);
  await tester.pumpAndSettle();
}

double _opacityOf(WidgetTester tester, String key) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  group('묶음 계산', () {
    test('석 달째 안 봄: 90일이 넘은 것만, 갈 곳 없는 캡처: 기타, 합은 중복 없이', () {
      final b = computeBundles([
        _shot(1, 10),
        _shot(2, 90), // 딱 90일은 아직
        _shot(3, 91),
        _shot(4, 3, category: Category.etc),
        _shot(5, 120, category: Category.etc), // 둘 다
      ], _now);
      expect(b.stale.map((s) => s.id), [3, 5]);
      expect(b.etc.map((s) => s.id), [4, 5]);
      expect(b.all.map((s) => s.id), [3, 5, 4]);
      expect(b.twinsReady, isFalse);
    });

    test('휴지통·분석 제외(skip)는 모든 묶음에서 빠진다', () {
      final b = computeBundles(
        [_shot(3, 91), _shot(4, 3, category: Category.etc)],
        _now,
        skip: {'a3', 'a4'},
      );
      expect(b.isEmpty, isTrue);
    });

    test('이번 주(월요일 시작): 요일별 장수, 크기를 아는 것만 용량 합, 오늘은 수요일 칸', () {
      expect(weekStart(_now), DateTime(2026, 10, 19));
      final w = weekOf(
        [
          TrashLogEntry(DateTime(2026, 10, 18, 23), 999), // 지난 일요일
          TrashLogEntry(DateTime(2026, 10, 19, 1), 1000),
          TrashLogEntry(DateTime(2026, 10, 21, 9)), // 크기 기록 전
          TrashLogEntry(DateTime(2026, 10, 21, 11), 500),
        ],
        _now,
        40,
      );
      expect(w.counts, [1, 0, 2, 0, 0, 0, 0]);
      expect(w.cleared, 3);
      expect(w.bytes, 1500);
      expect(w.remaining, 40);
      expect(w.todayIndex, 2);
      expect(
        weekOf([TrashLogEntry(DateTime(2026, 10, 20))], _now, 1).bytes,
        isNull,
        reason: '이번 주 용량을 전혀 모르면 null',
      );
    });

    test('확보 용량 단위: KB/MB/GB 자동, 소수 한 자리(.0은 뺀다)', () {
      expect(bytesLabel(350 * 1024), '350KB');
      expect(bytesLabel(18 * 1024 * 1024), '18MB');
      expect(bytesLabel((2.46 * 1024 * 1024).round()), '2.5MB');
      expect(bytesLabel((1.24 * 1024 * 1024 * 1024).round()), '1.2GB');
    });

    test('용량 문구: 0이면 없음, 작으면 MB, 크면 소수 한 자리 GB', () {
      expect(sizeLabel(0), isNull);
      expect(sizeLabel(10 * 1024 * 1024), '약 10MB');
      expect(sizeLabel((1.24 * 1024 * 1024 * 1024).round()), '약 1.2GB');
      expect(sizeLabel(12 * 1024 * 1024 * 1024), '약 12GB');
    });
  });

  group('쌍둥이 캡처', () {
    final t0 = DateTime(2026, 10, 20, 9);
    TwinInput twin(
      String id,
      int sec,
      String text, {
      String app = 'INSTAGRAM',
    }) => TwinInput(id, app, t0.add(Duration(seconds: sec)), text);
    const page = '성수동 브런치 카페 메뉴판 아메리카노 사천오백원 라떼 오천원';

    test('글자 바이그램 Jaccard: 같으면 1, 공백은 무시', () {
      expect(textSimilarity(page, page.replaceAll(' ', '')), 1);
      expect(textSimilarity('가나다라', '마바사아'), 0);
      expect(textSimilarity('가나다', '가나다라'), closeTo(2 / 3, 1e-9));
    });

    test('같은 앱·60초 안·유사도 0.9 이상만 묶고, 묶음 안은 최신순', () {
      expect(findTwins([twin('a', 0, page), twin('b', 30, page)]), [
        ['b', 'a'],
      ]);
      expect(
        findTwins([twin('a', 0, page), twin('b', 61, page)]),
        isEmpty,
        reason: '61초는 창 밖',
      );
      expect(
        findTwins([twin('a', 0, page), twin('b', 10, page, app: 'NAVER')]),
        isEmpty,
        reason: '다른 앱',
      );
      expect(
        findTwins([twin('a', 0, page), twin('b', 10, '$page 쿠폰 적용 시 삼천원 할인')]),
        isEmpty,
        reason: '유사도 0.9 미만',
      );
      expect(
        findTwins([twin('a', 0, '가'), twin('b', 10, '가')]),
        isEmpty,
        reason: '글자가 없으면(2자 미만) 뺀다',
      );
    });

    test('창 안에서 이어지면 한 묶음(a–b 50초, b–c 50초 → a·b·c)', () {
      expect(
        findTwins([
          twin('a', 0, page),
          twin('b', 50, page),
          twin('c', 100, page),
        ]),
        [
          ['c', 'b', 'a'],
        ],
      );
    });

    test('후보는 같은 앱 캡처가 60초 안에 더 있는 것만', () {
      ScreenshotItem item(int id, int sec, String? app) => ScreenshotItem(
        id: id,
        localAssetId: 'a$id',
        takenAt: t0.add(Duration(seconds: sec)),
        category: Category.info,
        tags: const [],
        sourceApp: app,
      );
      expect(
        twinCandidates([
          item(1, 0, 'INSTAGRAM'),
          item(2, 40, 'INSTAGRAM'),
          item(3, 500, 'INSTAGRAM'),
          item(4, 10, 'NAVER'),
          item(5, 20, null),
        ]).map((s) => s.id),
        [1, 2],
      );
    });

    testWidgets('묶음 화면: 쌍둥이끼리 붙여 보여 주고, 묶음마다 가장 최근 1장은 선택하지 않는다', (
      tester,
    ) async {
      final ocr = InMemoryOcrStore();
      ScreenshotItem item(int id, int sec) => ScreenshotItem(
        id: id,
        localAssetId: 'a$id',
        takenAt: t0.add(Duration(seconds: sec)),
        category: Category.place,
        tags: const [],
        sourceApp: 'INSTAGRAM',
      );
      final seed = [item(1, 0), item(2, 20), item(3, 40), item(4, 3000)];
      for (final s in seed) {
        await ocr.save(
          OcrRecord(
            assetId: s.localAssetId,
            fileName: 'Screenshot_${s.id}.jpg',
            modifiedAt: 1,
            text: s.id == 4 ? '전혀 다른 화면입니다' : page,
            charCount: 10,
            ocrAt: t0,
            engine: 'test',
          ),
        );
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RemineApp(
          repository: FakeScreenshotRepository(now: () => _now, seed: seed),
          now: () => _now,
          device: fakeServices(
            FakeGalleryReader(),
            store: ocr,
            trash: InMemoryTrashStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('정리'));
      // 쌍둥이 비교는 다른 isolate에서 돈다 → 화면 시계와 실제 시간을 번갈아 흘려 결과를 기다린다.
      for (var i = 0; i < 20 && find.text('거의 똑같아요').evaluate().isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pumpAndSettle();

      expect(find.text('거의 똑같아요'), findsOneWidget);
      expect(
        find.bySemanticsLabel('비슷한 스크린샷 2장. 거의 똑같아요'),
        findsOneWidget,
        reason: '3장 중 가장 최근 1장은 남긴다',
      );

      await _tap(tester, find.byKey(const ValueKey('tidy-twins')));
      expect(find.text('비슷한 스크린샷 3장'), findsOneWidget);
      expect(find.text('휴지통으로 2장'), findsOneWidget);
      bool selected(int id) => tester
          .widget<SelectableThumb>(
            find.descendant(
              of: find.byKey(ValueKey('tidy-shot-$id')),
              matching: find.byType(SelectableThumb),
            ),
          )
          .selected;
      expect(selected(3), isFalse, reason: '가장 최근 1장은 남긴다');
      expect(selected(2), isTrue);
      expect(selected(1), isTrue);
    });
  });

  group('꾹 눌러 크게 보기', () {
    Future<List<MethodCall>> pumpBundle(
      WidgetTester tester, {
      bool reduce = false,
      FakeGalleryReader? reader,
    }) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final items = [
        for (var i = 1; i <= 12; i++)
          ScreenshotItem(
            id: i,
            localAssetId: 'a$i',
            takenAt: DateTime(2026, 11, 6, 13, 58),
            category: Category.etc,
            tags: const [],
            sourceApp: 'KAKAOTALK',
          ),
      ];
      await tester.pumpWidget(
        RemineScope(
          store: RemineStore(FakeScreenshotRepository(now: () => _now)),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 800),
                disableAnimations: reduce,
              ),
              child: () {
                final screen = TidyBundleScreen(
                  title: '갈 곳 없는 캡처',
                  sections: [TidySection('갈 곳 없는 캡처', items)],
                );
                return reader == null
                    ? screen
                    : DeviceScope(
                        services: fakeServices(reader),
                        child: screen,
                      );
              }(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return calls;
    }

    bool selected(WidgetTester tester, int id) => tester
        .widget<SelectableThumb>(
          find.descendant(
            of: find.byKey(ValueKey('tidy-shot-$id')),
            matching: find.byType(SelectableThumb),
          ),
        )
        .selected;

    testWidgets('꾹 누르면 햅틱과 함께 크게, 손 떼면 닫히고 선택은 그대로', (tester) async {
      final calls = await pumpBundle(tester);
      expect(selected(tester, 2), isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tidy-shot-2'))),
      );
      await tester.pump(AppTidy.peekPress + const Duration(milliseconds: 20));
      await tester.pump(); // 비율 읽기
      await tester.pump(AppTidy.peekOpen);
      expect(find.byType(PeekPreview), findsOneWidget);
      expect(
        find.text('2026.11.06 (FRI)  |  13:58  ·  KAKAO TALK'),
        findsOneWidget,
      );
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate'),
        isNotEmpty,
      );
      final photo = tester.getRect(
        find.descendant(
          of: find.byType(PeekPreview),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(photo.left, greaterThanOrEqualTo(AppTidy.peekSidePadding - 0.5));
      expect(
        photo.width / photo.height,
        closeTo(AppTidy.peekFallbackAspect, 0.01),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(PeekPreview), findsNothing);
      expect(selected(tester, 2), isTrue, reason: '꾹 누르기는 선택을 바꾸지 않는다');

      await tester.tap(find.byKey(const ValueKey('tidy-shot-2')));
      await tester.pump();
      expect(selected(tester, 2), isFalse, reason: '탭은 지금처럼 선택/해제');
    });

    testWidgets('손가락이 닿는 순간 원본을 읽기 시작하고, 0.3초가 지나야 뜨고, 다 열린 뒤 원본으로 바뀐다', (
      tester,
    ) async {
      final reader = FakeGalleryReader()..decodableOriginals.add('a3');
      await pumpBundle(tester, reader: reader);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tidy-shot-3'))),
      );
      await tester.pump();
      expect(reader.bytesAsked, ['a3'], reason: '꾹 누름이 인식되기 전에 시작');

      await tester.pump(AppTidy.peekPress - const Duration(milliseconds: 60));
      expect(find.byType(PeekPreview), findsNothing, reason: '0.3초 전');
      await tester.pump(const Duration(milliseconds: 80));
      // 디코딩은 실제 시간이 든다 → 화면 시계와 실제 시간을 번갈아 흘린다.
      for (
        var i = 0;
        i < 30 &&
            find.byKey(const ValueKey('peek-original')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PeekPreview), findsOneWidget);
      expect(find.byKey(const ValueKey('peek-original')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(PeekPreview), findsNothing);
    });

    testWidgets('누르자마자 움직이면 스크롤이 이기고 미리 보기는 안 뜬다', (tester) async {
      await pumpBundle(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tidy-shot-5'))),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(AppTidy.peekPress + const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(PeekPreview), findsNothing);
      expect(selected(tester, 5), isTrue);
    });

    testWidgets('애니메이션 줄이기면 커지는 효과 없이 바로', (tester) async {
      await pumpBundle(tester, reduce: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tidy-shot-1'))),
      );
      await tester.pump(AppTidy.peekPress + const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.byType(PeekPreview), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await gesture.up();
      await tester.pump();
      expect(find.byType(PeekPreview), findsNothing);
    });
  });

  group('이번 주 비운 스크린샷(D3 점선 도장)', () {
    Future<void> pumpWeek(WidgetTester tester, TidyWeek week) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: TidyWeekStamps(week: week),
            ),
          ),
        ),
      );
    }

    double opacityOfStamp(WidgetTester tester, int i) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byKey(ValueKey('stamp-$i')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('용량은 형광펜, 비운 쪽 막대는 실제 비율이 작아도 9%, 아직 안 온 요일은 흐리게', (
      tester,
    ) async {
      await pumpWeek(
        tester,
        const TidyWeek(
          counts: [0, 3, 0, 4, 0, 0, 0],
          bytes: 18 * 1024 * 1024,
          remaining: 120,
          todayIndex: 3, // 목요일
        ),
      );
      expect(find.text('18MB'), findsOneWidget);
      expect(find.byKey(const ValueKey('week-highlight')), findsOneWidget);
      expect(find.text('확보했어요'), findsOneWidget);
      expect(find.text('남은 120장'), findsOneWidget);
      expect(find.text('비운 7장'), findsOneWidget);
      expect(
        find.bySemanticsLabel('이번 주 7장 비움, 18MB 확보, 화요일 3장 목요일 4장'),
        findsOneWidget,
      );

      final remaining = tester.getSize(
        find.byKey(const ValueKey('bar-remaining')),
      );
      final cleared = tester.getSize(find.byKey(const ValueKey('bar-cleared')));
      final share = cleared.width / (remaining.width + cleared.width);
      expect(
        share,
        closeTo(AppTidy.barMinCleared, 0.01),
        reason: '7/127은 9%로 올린다',
      );
      expect(cleared.height, AppTidy.barHeight);

      for (final i in [0, 1, 2, 3]) {
        expect(opacityOfStamp(tester, i), 1, reason: '지난 요일·오늘 $i');
      }
      for (final i in [4, 5, 6]) {
        expect(
          opacityOfStamp(tester, i),
          AppTidy.futureOpacity,
          reason: '아직 안 온 $i',
        );
      }
      final today = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('stamp-3')),
          matching: find.text('목'),
        ),
      );
      expect(today.style!.color, AppTidy.dash);
      expect(today.style!.fontWeight, FontWeight.w800);
    });

    testWidgets('이번 주 용량을 전혀 모르면 용량 자리에 장수를 크게', (tester) async {
      await pumpWeek(
        tester,
        const TidyWeek(
          counts: [2, 5, 0, 0, 0, 0, 0],
          bytes: null,
          remaining: 30,
          todayIndex: 1,
        ),
      );
      expect(find.text('7장', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('week-highlight')), findsOneWidget);
      expect(
        find.bySemanticsLabel('이번 주 7장 비움, 월요일 2장 화요일 5장'),
        findsOneWidget,
      );
    });

    testWidgets('0장이면 막대는 차콜만, "비운 0장", 용량은 "아직 0MB"(형광펜 없음)', (tester) async {
      await pumpWeek(
        tester,
        const TidyWeek(
          counts: [0, 0, 0, 0, 0, 0, 0],
          bytes: null,
          remaining: 30,
          todayIndex: 0,
        ),
      );
      expect(find.text('아직 0MB', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('week-highlight')), findsNothing);
      expect(find.byKey(const ValueKey('bar-cleared')), findsNothing);
      expect(find.byKey(const ValueKey('bar-remaining')), findsOneWidget);
      expect(find.text('비운 0장'), findsOneWidget);
      expect(find.bySemanticsLabel('이번 주 0장 비움'), findsOneWidget);
    });
  });

  group('정리 탭 세로 여백', () {
    /// (제목 위에 더한 높이, 이번 주 막대 아래 ~ 탭바 사이 높이)
    Future<(double, double)> measure(
      WidgetTester tester,
      Size size, {
      double scale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final trash = InMemoryTrashStore();
      await trash.add(
        TrashedShot(
          assetId: 'x',
          category: Category.etc,
          takenAt: _now,
          trashedAt: _now,
          onServer: false,
        ),
      );
      await tester.pumpWidget(
        RemineApp(
          repository: FakeScreenshotRepository(now: () => _now),
          now: () => _now,
          device: fakeServices(FakeGalleryReader(), trash: trash),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byIcon(LucideIcons.broom)); // 이미 정리 탭이어도 된다
      final gap = tester
          .getSize(find.byKey(const ValueKey('tidy-top-gap')))
          .height;
      final below =
          tester.getRect(find.byType(AppTabBar)).top -
          tester.getRect(find.bySemanticsLabel(RegExp('^이번 주 .*장 비움'))).bottom;
      return (gap, below);
    }

    testWidgets('남는 높이의 15%(최대 48)를 제목 위에: 큰 화면일수록 더 내려가고 아래 빈칸은 준다', (
      tester,
    ) async {
      final (smallGap, smallBelow) = await measure(
        tester,
        const Size(360, 800),
      );
      final (bigGap, bigBelow) = await measure(tester, const Size(412, 915));

      // 위에 더한 만큼 아래 빈칸이 줄었다: 더하기 전 남는 높이 = gap + below(+ 아래 여백 24).
      double expected(double gap, double below) => math.max(
        0,
        math.min(
          AppTidy.topGrowMax,
          (gap + below - AppSpacing.s24) * AppTidy.topGrowShare,
        ),
      );
      expect(smallGap, closeTo(expected(smallGap, smallBelow), 0.5));
      expect(bigGap, closeTo(expected(bigGap, bigBelow), 0.5));
      expect(smallGap, lessThan(24), reason: '360×800은 거의 그대로');
      expect(bigGap, greaterThan(smallGap * 1.5), reason: '412×915는 더 내려간다');
    });

    testWidgets('내용이 화면보다 길면(작은 화면·글자 1.3배) 위 여백을 더하지 않고 스크롤', (tester) async {
      final (gap, _) = await measure(tester, const Size(360, 640), scale: 1.3);
      expect(gap, 0);
    });
  });

  group('정리 탭 벤토', () {
    testWidgets('세 묶음이 다 비면 큰 타일은 "지금은 정리할 게 없어요"·버튼 없음, 0인 타일은 흐리고 안 눌린다', (
      tester,
    ) async {
      await _pumpTidy(tester, seed: [_shot(1, 1), _shot(2, 2)]);

      expect(find.text('지금은 정리할 게 없어요'), findsOneWidget);
      expect(find.text('한 번에 보기 →'), findsNothing);
      for (final key in ['tidy-twins', 'tidy-stale', 'tidy-etc']) {
        expect(_opacityOf(tester, key), AppTidy.emptyOpacity, reason: key);
      }
      await _tap(tester, find.byKey(const ValueKey('tidy-stale')));
      expect(find.byType(TidyBundleScreen), findsNothing, reason: '0이면 못 누른다');
    });

    testWidgets('묶음 화면: 처음엔 전부 선택, 골라서 휴지통으로 → 되돌리기', (tester) async {
      await _pumpTidy(
        tester,
        seed: [_shot(1, 100), _shot(2, 200), _shot(3, 1)],
      );
      expect(_opacityOf(tester, 'tidy-stale'), 1);

      await _tap(tester, find.byKey(const ValueKey('tidy-stale')));
      expect(find.text('3달째 안 봄 2장'), findsOneWidget);
      expect(find.text('휴지통으로 2장'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('tidy-shot-2')));
      expect(find.text('휴지통으로 1장'), findsOneWidget);

      await _tap(tester, find.text('휴지통으로 1장'));
      expect(find.text('3달째 안 봄 1장'), findsOneWidget);
      expect(find.text('1장을 휴지통으로 옮겼어요'), findsOneWidget);

      await _tap(tester, find.text('되돌리기'));
      expect(find.text('3달째 안 봄 2장'), findsOneWidget);
    });

    testWidgets('한 번에 보기: 묶음별 소제목으로 나누고, 두 묶음에 든 캡처는 앞 묶음에만', (tester) async {
      await _pumpTidy(
        tester,
        seed: [
          _shot(1, 100),
          _shot(2, 3, category: Category.etc),
          _shot(3, 120, category: Category.etc),
        ],
      );
      await _tap(tester, find.text('한 번에 보기 →'));

      expect(find.text('비울 수 있는 스크린샷 3장'), findsOneWidget);
      expect(find.text('3달째 안 봄 2장'), findsOneWidget);
      expect(find.text('갈 곳 없는 스크린샷 1장'), findsOneWidget);
      expect(find.byKey(const ValueKey('tidy-shot-3')), findsOneWidget);
    });

    testWidgets('용량은 묶음 캡처만 읽고, 탭을 다시 열어도 다시 읽지 않는다', (tester) async {
      final reader = FakeGalleryReader()
        ..sizes['a1'] = 300 * 1024 * 1024
        ..sizes['a2'] = 300 * 1024 * 1024;
      await _pumpTidy(
        tester,
        seed: [
          _shot(1, 100),
          _shot(2, 3, category: Category.etc),
          _shot(3, 1),
        ],
        reader: reader,
      );
      expect(find.text('약 0.6GB 가벼워져요'), findsOneWidget);
      expect(reader.sizeAsked.toSet(), {'a1', 'a2'}, reason: '묶음 밖(a3)은 안 읽는다');

      await _tap(tester, find.text('서랍'));
      await _tap(tester, find.text('정리'));
      expect(reader.sizeAsked, hasLength(2));
    });

    testWidgets('다시 계산은 캡처 목록·휴지통이 바뀌었을 때만', (tester) async {
      late _CountingRepo repo;
      await _pumpTidy(
        tester,
        seed: [_shot(1, 100), _shot(2, 1)],
        wrap: (base) => repo = _CountingRepo(base),
      );
      final first = repo.allCalls;
      expect(first, greaterThan(0));

      await _tap(tester, find.text('서랍'));
      await _tap(tester, find.text('정리'));
      expect(repo.allCalls, first, reason: '바뀐 게 없으면 다시 안 센다');

      await _tap(tester, find.byKey(const ValueKey('tidy-stale')));
      await _tap(tester, find.text('휴지통으로 1장'));
      await tester.pumpAndSettle();
      expect(repo.allCalls, greaterThan(first), reason: '휴지통으로 보내면 다시 센다');
      expect(find.byKey(const ValueKey('tidy-stale')), findsOneWidget);
      expect(_opacityOf(tester, 'tidy-stale'), AppTidy.emptyOpacity);
    });
  });
}
