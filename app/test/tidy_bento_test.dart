import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/screenshot_repository.dart';
import 'package:remine/data/tidy_bundles.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/category_summary.dart';
import 'package:remine/models/category_update.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/tidy_bundle_screen.dart';
import 'package:remine/widgets/selectable_thumb.dart';

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

    test('이번 주(월~일) 요일별 장수: 지난주는 빼고 오늘은 수요일 칸', () {
      expect(weekStart(_now), DateTime(2026, 10, 19));
      expect(
        weekCounts([
          DateTime(2026, 10, 18, 23), // 지난 일요일
          DateTime(2026, 10, 19, 1),
          DateTime(2026, 10, 21, 9),
          DateTime(2026, 10, 21, 11),
        ], _now),
        [1, 0, 2, 0, 0, 0, 0],
      );
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
        find.bySemanticsLabel('쌍둥이 캡처 2장. 거의 똑같아요'),
        findsOneWidget,
        reason: '3장 중 가장 최근 1장은 남긴다',
      );

      await _tap(tester, find.byKey(const ValueKey('tidy-twins')));
      expect(find.text('쌍둥이 캡처 3장'), findsOneWidget);
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
      expect(find.text('석 달째 안 봄 2장'), findsOneWidget);
      expect(find.text('휴지통으로 2장'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('tidy-shot-2')));
      expect(find.text('휴지통으로 1장'), findsOneWidget);

      await _tap(tester, find.text('휴지통으로 1장'));
      expect(find.text('석 달째 안 봄 1장'), findsOneWidget);
      expect(find.text('1장을 휴지통으로 옮겼어요'), findsOneWidget);

      await _tap(tester, find.text('되돌리기'));
      expect(find.text('석 달째 안 봄 2장'), findsOneWidget);
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

      expect(find.text('비울 수 있는 캡처 3장'), findsOneWidget);
      expect(find.text('석 달째 안 봄 2장'), findsOneWidget);
      expect(find.text('갈 곳 없는 캡처 1장'), findsOneWidget);
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
