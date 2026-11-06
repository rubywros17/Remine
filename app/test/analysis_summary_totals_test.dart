import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/analysis_screen.dart';

/// 완료 요약은 이번 실행 개수가 아니라 홈 막대와 같은 저장소 요약(휴지통 제외, 기기 분류 포함)을 쓴다.
void main() {
  final now = DateTime(2026, 11, 6, 12);

  ScreenshotItem shot(int id, Category c) => ScreenshotItem(
    id: id,
    localAssetId: 's$id',
    takenAt: now.subtract(Duration(hours: id)),
    category: c,
    tags: const [],
  );

  /// 서버: 쇼핑 3(1장 휴지통) · 정보 1. 기기: 대화 4(1장 휴지통) + 숨김(금융) 1.
  /// → 홈 막대: 대화 3 · 쇼핑 2 · 정보 1.
  Future<RemineStore> store() async {
    final base = FakeScreenshotRepository(
      now: () => now,
      seed: [
        shot(1, Category.shopping),
        shot(2, Category.shopping),
        shot(3, Category.shopping),
        shot(4, Category.info),
      ],
    );
    final verdicts = InMemoryLocalVerdictStore();
    Future<void> put(String id, String fileName) => verdicts.save(
      StoredVerdict.of(
        judgeByApp(fileName)!,
        assetId: id,
        takenAt: now,
        modifiedAt: 1,
        now: now,
      ),
    );
    for (var i = 0; i < 4; i++) {
      await put('chat$i', 'Screenshot_20261106_12000${i}_KakaoTalk.jpg');
    }
    await put('bank', 'Screenshot_20261106_120009_KakaoBank.jpg');
    final trash = InMemoryTrashStore();
    await trash.add(
      TrashedShot(
        assetId: 'chat0',
        category: Category.chat,
        takenAt: now,
        trashedAt: now,
        onServer: false,
      ),
    );
    final s = RemineStore(
      LocalMergedRepository(base, verdicts, trash: trash),
      now: () => now,
    );
    await s.trash(1);
    return s;
  }

  /// 이번 실행은 정보 5장만 정리했다(전체와 다른 값).
  SyncStatus thisRun() {
    final status = SyncStatus()..begin(5);
    for (var i = 0; i < 5; i++) {
      status.count(Category.info);
    }
    return status
      ..advance(5)
      ..finish();
  }

  Future<void> pump(WidgetTester tester, RemineStore s) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RemineScope(
        store: s,
        child: MaterialApp(
          home: AnalysisScreen(status: thisRun(), onHome: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('저장소가 있으면 홈 막대와 같은 값(휴지통 제외, 기기 분류 포함)으로 요약한다', (tester) async {
    final s = await tester.runAsync(store);
    await pump(tester, s!);

    final home = (await tester.runAsync(s.repository.summary))!;
    final expected =
        (home.categories.where((c) => c.count > 0).toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .map((c) => '${c.category.label} ${c.count}장')
            .join(' · ');
    expect(expected, '대화 3장 · 쇼핑 2장 · 정보 1장');
    expect(find.text(expected), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('summary-highlight')),
        matching: find.text('대화'),
      ),
      findsOneWidget,
      reason: '최다는 대화(기기 분류)',
    );
  });

  testWidgets('이번 실행 개수와 전체가 다르면 전체를 따른다', (tester) async {
    final s = await tester.runAsync(store);
    await pump(tester, s!);

    expect(find.text('정보 5장'), findsNothing, reason: '이번 실행 개수를 쓰면 안 된다');
    expect(find.textContaining('정보 1장'), findsOneWidget);
  });
}
