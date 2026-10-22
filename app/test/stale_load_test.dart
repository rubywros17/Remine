import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/screens/category_screen.dart';

/// 목록 응답이 늦게 도착하는 상황을 만든다: 다음 `list` 호출은 호출 시점의 데이터를 잡아 두고 [gate]가 열릴 때까지 기다린다.
class _LaggyRepository extends FakeScreenshotRepository {
  _LaggyRepository({super.now});

  Completer<void>? gate;

  /// [gate]를 걸기 전에 그냥 통과시킬 `list` 호출 수(화면은 태그용 전체 목록 → 그리드용 목록 순서로 부른다).
  int passFirst = 0;

  @override
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) async {
    final snapshot = await super.list(
      category: category,
      tag: tag,
      page: page,
      size: size,
    );
    final wait = gate;
    if (wait != null) {
      if (passFirst > 0) {
        passFirst--;
      } else {
        gate = null; // 한 호출만 늦춘다
        await wait.future;
      }
    }
    return snapshot;
  }
}

void main() {
  testWidgets('늦게 도착한 옛 목록이 최신 목록을 덮어쓰지 않는다 (카테고리 수정 직후 그리드)', (tester) async {
    final repo = _LaggyRepository(now: () => DateTime(2026, 10, 19, 12));
    final store = RemineStore(repo, now: () => DateTime(2026, 10, 19, 12));
    await tester.pumpWidget(
      RemineScope(
        store: store,
        child: const MaterialApp(
          home: CategoryScreen(category: Category.shopping),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tile-5')), findsOneWidget);

    // ① 옛 데이터를 읽은 목록 요청이 늦어진다(동기화 배치가 끝나 홈이 새로 불러오는 상황과 같다).
    final gate = Completer<void>();
    repo.passFirst = 1; // 그리드가 쓰는 두 번째 목록 요청을 늦춘다
    repo.gate = gate;
    store.refresh();
    await tester.pump();

    // ② 그 사이 사용자가 카테고리를 바꾼다 → 새 목록 요청이 먼저 끝난다.
    await store.changeCategory(5, Category.info);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tile-5')), findsNothing);

    // ③ 늦던 옛 응답이 이제 도착해도 화면은 바뀐 상태를 유지해야 한다.
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tile-5')),
      findsNothing,
      reason: '옛 응답이 그리드를 되돌렸다',
    );
  });
}
