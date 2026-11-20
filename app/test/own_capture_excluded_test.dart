import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/excluded_screen.dart';

import 'support/fake_device.dart';

// Remine 자기 캡처(APP_OWN)를 포함한 숨김 판정: "분석 제외"에서만 보이고, 휴지통·되살리기를 거쳐도 서랍·관심사·정리 탭엔 안 나온다.
final _now = DateTime(2026, 11, 20, 12);

const _own = LocalVerdict(
  route: LocalRoute.deviceOnly,
  category: Category.etc,
  hidden: true,
  reasons: [ReasonCode.appOwn],
);

void main() {
  late InMemoryLocalVerdictStore verdicts;
  late InMemoryTrashStore trash;
  late FakeScreenshotRepository base;
  late LocalMergedRepository merged;

  Future<void> put(String id, LocalVerdict v, int minutesAgo) => verdicts.save(
    StoredVerdict.of(
      v,
      assetId: id,
      takenAt: _now.add(Duration(days: 1, minutes: -minutesAgo)),
      modifiedAt: 1,
      now: _now,
    ),
  );

  Future<int> idOf(String assetId) async =>
      -(await verdicts.find(assetId))!.localId;

  setUp(() async {
    verdicts = InMemoryLocalVerdictStore();
    trash = InMemoryTrashStore();
    base = FakeScreenshotRepository(now: () => _now);
    merged = LocalMergedRepository(base, verdicts, trash: trash);
    await put('card1', judgeByText('카드 4111 1111 1111 1111'), 1);
    await put(
      'bank1',
      judgeByApp('Screenshot_20261019_120000_KakaoBank.jpg')!,
      2,
    );
    await put('own1', _own, 3);
    await put(
      'chat1',
      judgeByApp('Screenshot_20261019_120000_KakaoTalk.jpg')!,
      4,
    );
  });

  const hiddenIds = ['card1', 'bank1', 'own1'];

  /// 숨김 3종이 서랍 요약·카테고리 목록·관심사·정리 탭(all) 어디에도 없다.
  Future<void> expectNowhereVisible() async {
    final b = await base.summary();
    final m = await merged.summary();
    expect(m.total, b.total + 1, reason: '메신저(CHAT) 1장만 더해진다');
    expect(m.of(Category.etc).count, b.of(Category.etc).count);
    for (final c in Category.values) {
      final ids = (await merged.list(
        category: c,
        size: 500,
      )).items.map((s) => s.localAssetId);
      expect(ids, isNot(anyOf([for (final h in hiddenIds) contains(h)])));
      expect(
        m.of(c).recentAssetIds,
        isNot(anyOf([for (final h in hiddenIds) contains(h)])),
      );
    }
    final all = (await merged.all()).map((s) => s.localAssetId);
    expect(all, contains('chat1'));
    expect(all, isNot(anyOf([for (final h in hiddenIds) contains(h)])));
    expect(
      (await merged.interests()).map((i) => i.tag),
      (await base.interests()).map((i) => i.tag),
      reason: '관심사는 서버 집계뿐(숨김은 서버에 없다)',
    );
  }

  test(
    '숨김 판정(민감·금융·Remine 화면)은 분석 제외에만 있고, 휴지통 → 되살리기 뒤에도 분석 제외로만 돌아온다',
    () async {
      await expectNowhereVisible();
      expect((await loadExcluded(verdicts, trash)).map((v) => v.assetId), [
        'card1',
        'bank1',
        'own1',
      ]);

      await merged.trash(await idOf('own1'));
      await merged.trash(await idOf('bank1'));
      expect(
        (await trash.all()).map((t) => t.assetId),
        unorderedEquals(['own1', 'bank1']),
      );
      expect((await trash.all()).every((t) => !t.onServer), isTrue);
      expect((await loadExcluded(verdicts, trash)).map((v) => v.assetId), [
        'card1',
      ]);
      await expectNowhereVisible();

      await merged.restore(await idOf('own1'));
      await merged.restore(await idOf('bank1'));
      expect(await trash.all(), isEmpty);
      expect((await loadExcluded(verdicts, trash)).map((v) => v.assetId), [
        'card1',
        'bank1',
        'own1',
      ]);
      await expectNowhereVisible();
    },
  );

  testWidgets('분석 제외 화면: "Remine 화면" 라벨, 두 장 골라 휴지통 → 목록에서 빠지고 되돌리기로 돌아온다', (
    tester,
  ) async {
    final store = RemineStore(merged);
    await tester.pumpWidget(
      RemineScope(
        store: store,
        child: MaterialApp(
          home: ExcludedScreen(
            verdicts: verdicts,
            trash: trash,
            reader: FakeGalleryReader(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remine 화면'), findsOneWidget);
    expect(find.text('금융 앱'), findsOneWidget);
    expect(find.textContaining('휴지통으로'), findsNothing, reason: '처음엔 아무것도 안 고름');

    await tester.tap(find.byKey(const ValueKey('excluded-own1')));
    await tester.tap(find.byKey(const ValueKey('excluded-bank1')));
    await tester.pump();
    await tester.tap(find.text('휴지통으로 2장'));
    await tester.pumpAndSettle();

    expect(find.text('Remine 화면'), findsNothing);
    expect(find.text('금융 앱'), findsNothing);
    expect(find.text('카드번호'), findsOneWidget);
    expect(find.text('2장을 휴지통으로 옮겼어요'), findsOneWidget);
    expect(store.revision, greaterThan(0), reason: '홈 알약 개수가 다시 센다');

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text('Remine 화면'), findsOneWidget);
    expect(find.text('금융 앱'), findsOneWidget);
  });
}
