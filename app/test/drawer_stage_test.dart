import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/widgets/app_button.dart';
import 'package:remine/widgets/drawer_stage.dart';

/// 첫 분석 화면의 카드 → 서랍 모션: 타이밍·큐 간격·동시 비행 수·모션 줄이기·배치.
void main() {
  Future<SyncStatus> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool reduced = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final status = SyncStatus()..begin(300);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: reduced),
          child: AnalysisScreen(status: status, onHome: () {}),
        ),
      ),
    );
    return status;
  }

  void feed(SyncStatus status, int n, {Category c = Category.shopping}) {
    for (var i = 0; i < n; i++) {
      status.count(c, assetId: 'a${status.shots.length}');
    }
    status.advance(n);
  }

  // 칸 숫자: 스테이지 안의 텍스트로만 찾는다(큰 진행 숫자와 구분).
  Finder binNumber(String text) =>
      find.descendant(of: find.byType(DrawerStage), matching: find.text(text));

  Iterable<DrawerFlightCard> cards(WidgetTester tester) =>
      tester.widgetList<DrawerFlightCard>(find.byType(DrawerFlightCard));

  int flying(WidgetTester tester) =>
      cards(tester)
          .where((c) => c.fly.status == AnimationStatus.forward)
          .length;

  testWidgets('카드는 등장·이름표·멈춤(680ms) 뒤 460ms 날아가 칸에 들어가고, 그때 숫자가 +1 된다', (
    tester,
  ) async {
    final status = await mount(tester);
    feed(status, 1);
    await tester.pump();
    expect(cards(tester), hasLength(1));
    expect(flying(tester), 0);

    await tester.pump(const Duration(milliseconds: 679));
    expect(flying(tester), 0, reason: '멈춤이 끝나기 전');
    await tester.pump(const Duration(milliseconds: 2));
    expect(flying(tester), 1);
    expect(binNumber('1'), findsNothing, reason: '날아가는 동안은 아직 +1 전');

    await tester.pump(const Duration(milliseconds: 1)); // 비행 첫 프레임
    await tester.pump(const Duration(milliseconds: 459));
    expect(binNumber('1'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(cards(tester), isEmpty);
    expect(binNumber('1'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('카드 간격은 600ms, 큐가 20장을 넘으면 300ms로 줄어든다', (tester) async {
    final status = await mount(tester);
    int started() => status.shots.length - queued(tester);

    feed(status, 5);
    await tester.pump();
    expect(started(), 1);
    await tester.pump(const Duration(milliseconds: 599));
    expect(started(), 1);
    await tester.pump(const Duration(milliseconds: 2));
    expect(started(), 2);
    await tester.pumpAndSettle();

    feed(status, 30);
    await tester.pump();
    final before = started();
    await tester.pump(const Duration(milliseconds: 301));
    expect(started(), before + 1, reason: '큐 29장 → 300ms');
    await tester.pumpAndSettle();
  });

  testWidgets('동시에 날아가는 카드는 2장을 넘지 않는다', (tester) async {
    final status = await mount(tester);
    feed(status, 40);
    var most = 0;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final now = flying(tester);
      if (now > most) most = now;
    }
    expect(most, AnalysisStage.maxFlying);
    await tester.pumpAndSettle();
    expect(binNumber('40'), findsOneWidget, reason: '40장이 빠짐없이 들어갔다');
  });

  testWidgets('숨김 캡처는 카드 없이 칸 숫자만 바로 오른다', (tester) async {
    final status = await mount(tester);
    status.count(Category.etc);
    status.advance(1);
    await tester.pump();
    expect(cards(tester), isEmpty);
    expect(binNumber('1'), findsOneWidget);
  });

  testWidgets('모션 줄이기: 카드 없이 칸과 숫자만 바로 갱신한다', (tester) async {
    final status = await mount(tester, reduced: true);
    feed(status, 3);
    await tester.pump();
    expect(cards(tester), isEmpty);
    expect(binNumber('3'), findsOneWidget);
  });

  testWidgets('진행 중에 화면을 열면 이미 분류된 것은 다시 날리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final status = SyncStatus()..begin(10);
    feed(status, 4);
    await tester.pumpWidget(
      MaterialApp(
        home: AnalysisScreen(status: status, onHome: () {}),
      ),
    );
    await tester.pump();
    expect(cards(tester), isEmpty);
    expect(binNumber('4'), findsOneWidget);
  });

  testWidgets('새 실행이 시작되면 큐와 칸을 비운다', (tester) async {
    final status = await mount(tester);
    feed(status, 5);
    await tester.pump(const Duration(milliseconds: 100));
    status.begin(10);
    await tester.pump();
    expect(cards(tester), isEmpty);
    expect(binNumber('0'), findsNWidgets(Category.values.length));
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets('칸 배치 $size: 바닥·이름표 정렬, 상단·버튼과 겹치지 않음', (tester) async {
      final status = await mount(tester, size: size);
      for (final c in Category.values) {
        for (var i = 0; i <= c.index * 4; i++) {
          status.count(c);
        }
      }
      status.advance(1);
      await tester.pumpAndSettle();

      final labels = [
        for (final c in Category.values)
          tester.getRect(find.text(c.label).first),
      ];
      expect(labels.map((r) => r.center.dy.round()).toSet(), hasLength(1));

      final numbers = [
        for (final c in Category.values)
          tester.getRect(binNumber('${c.index * 4 + 1}')).top,
      ];
      for (var i = 1; i < numbers.length; i++) {
        expect(numbers[i], lessThan(numbers[i - 1]), reason: '많을수록 위로 자란다');
      }

      final stage = tester.getRect(find.byType(DrawerStage));
      expect(numbers.reduce((a, b) => a < b ? a : b), greaterThan(stage.top));
      expect(
        tester.getRect(find.text(keepScreenOnHint)).bottom,
        lessThanOrEqualTo(stage.top),
      );
      expect(labels.first.bottom, lessThanOrEqualTo(stage.bottom));
      expect(
        stage.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AppButton)).top),
      );
      // 버튼 → 보안 문구 순서
      expect(
        tester.getRect(find.byType(AppButton)).bottom,
        lessThanOrEqualTo(tester.getRect(find.text(PrivacyNote.text)).top),
      );
    });
  }
}

/// 아직 카드로 시작하지 않은 장수: 칸에 들어온 수 + 날고 있는 카드 수를 뺀 나머지.
int queued(WidgetTester tester) {
  final stage = tester.widget<DrawerStage>(find.byType(DrawerStage));
  final total = stage.status!.shots.length;
  final inAir = tester.widgetList(find.byType(DrawerFlightCard)).length;
  final landed = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(DrawerStage),
          matching: find.byWidgetPredicate(
            (w) => w is Text && int.tryParse(w.data ?? '') != null,
          ),
        ),
      )
      .map((t) => int.parse(t.data!))
      .fold(0, (a, b) => a + b);
  return total - inAir - landed;
}
