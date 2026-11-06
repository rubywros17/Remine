import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/widgets/app_button.dart';
import 'package:remine/widgets/drawer_stage.dart';

/// 첫 분석 화면의 카드 → 서랍 모션: 타이밍·큐 간격·동시 카드 수·완료 채우기·큰 숫자·모션 줄이기·배치.
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

  // 실행 중에는 진행 막대·대기 카드가 계속 움직여 pumpAndSettle이 끝나지 않는다. 시간만 흘려보낸다.
  Future<void> flush(WidgetTester tester, {int seconds = 40}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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

  // 칸 합계(스테이지 안의 숫자 텍스트).
  int binSum(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(DrawerStage),
          matching: find.byWidgetPredicate(
            (w) => w is Text && int.tryParse(w.data ?? '') != null,
          ),
        ),
      )
      .fold(0, (a, t) => a + int.parse(t.data!));

  // 큰 숫자(numHero, 128).
  int hero(WidgetTester tester) => int.parse(
    tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.style?.fontSize == 128)
        .data!,
  );

  // 링: 칸 막대 위의 테두리 상자. 카드 이름표에는 테두리가 없다.
  Finder rings() => find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border != null,
  );

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
    await flush(tester);
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
    await flush(tester);

    feed(status, 30);
    await tester.pump();
    final before = started();
    await tester.pump(const Duration(milliseconds: 301));
    expect(started(), before + 1, reason: '큐 29장 → 300ms');
    await flush(tester);
  });

  testWidgets('화면에 동시에 떠 있는 카드는 2장을 넘지 않고, 넘치는 장은 칸만 +1(링 유지) 된다', (
    tester,
  ) async {
    final status = await mount(tester);
    feed(status, 40);
    var most = 0;
    var ringWithoutThirdCard = false;
    await tester.pump();
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final now = cards(tester).length;
      if (now > most) most = now;
      if (now == AnalysisStage.maxCards && rings().evaluate().isNotEmpty) {
        ringWithoutThirdCard = true;
      }
    }
    expect(most, AnalysisStage.maxCards);
    expect(ringWithoutThirdCard, isTrue);
    await flush(tester);
    expect(binNumber('40'), findsOneWidget, reason: '40장이 빠짐없이 들어갔다');
  });

  testWidgets('큰 숫자는 서버 진행 수가 아니라 칸 합계다', (tester) async {
    final status = await mount(tester);
    status.advance(100);
    await tester.pump();
    expect(hero(tester), 0, reason: '서버 진행 수를 그대로 쓰지 않는다');

    feed(status, 3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(hero(tester), binSum(tester));
    await flush(tester);
    expect(hero(tester), 3);
    expect(binSum(tester), 3);
  });

  testWidgets('완료: 남은 큐를 카드 없이 40ms 간격으로 채우고, 큰 숫자와 칸이 같이 끝난다', (tester) async {
    final status = await mount(tester);
    for (var i = 0; i < 30; i++) {
      status.count(Category.values[i % Category.values.length], assetId: 'a$i');
    }
    status.advance(30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    status.finish();
    await tester.pump();
    expect(
      find.text('/ 300장 꺼냈어요'),
      findsOneWidget,
      reason: '채우는 동안은 아직 완료가 아니다',
    );
    expect(find.text('홈에서 먼저 볼래요'), findsOneWidget);
    final before = binSum(tester);
    final cardsBefore = cards(tester).length;
    await tester.pump(const Duration(milliseconds: 41));
    await tester.pump();
    expect(binSum(tester), greaterThan(before));
    expect(
      cards(tester).length,
      lessThanOrEqualTo(cardsBefore),
      reason: '새 카드 없음',
    );

    // 40ms × 큐 + 떠 있던 카드가 들어가는 시간 안에 끝난다.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(hero(tester), binSum(tester), reason: '항상 같이 움직인다');
    }
    await flush(tester);
    expect(hero(tester), 30);
    expect(binSum(tester), 30);
    expect(find.text('장 꺼냈어요'), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
  });

  group('진행 영역·간격', () {
    Rect slot(WidgetTester t) =>
        t.getRect(find.byKey(const ValueKey('analysis-progress')));
    Rect stage(WidgetTester t) => t.getRect(find.byType(DrawerStage));

    for (final size in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('진행 영역과 스테이지는 대기·묶음 사이·비행·완료 내내 같은 자리다 $size', (
        tester,
      ) async {
        final status = await mount(tester, size: size);
        await tester.pump();
        final slot0 = slot(tester);
        final stage0 = stage(tester);
        void same(String when) {
          expect(slot(tester), slot0, reason: when);
          expect(stage(tester), stage0, reason: when);
        }

        status.setWaiting(16);
        await tester.pump();
        expect(find.text('16장을 분류하는 중이에요…'), findsOneWidget);
        same('대기 중');

        status.setWaiting(0);
        feed(status, 3);
        await tester.pump();
        expect(
          find.text('16장을 분류하는 중이에요…'),
          findsOneWidget,
          reason: '묶음 사이에도 유지',
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        same('묶음 사이');

        await tester.pump(const Duration(milliseconds: 800));
        expect(cards(tester), isNotEmpty);
        same('카드 비행 중');

        status.finish(issue: SyncIssue.partial, failedCount: 2);
        await flush(tester, seconds: 5);
        expect(find.text('장 꺼냈어요'), findsOneWidget);
        expect(find.text('2장은 다음에 다시 분류해요'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        same('완료');
      });
    }

    test('간격: 남은 시간을 큐에 나누고 600~4000ms로 제한한다', () {
      Duration gap(int queue, Duration? until, {bool draining = false}) =>
          drawerGap(queue: queue, untilNextBatch: until, draining: draining);
      const s72 = Duration(seconds: 72);
      expect(gap(16, s72), const Duration(milliseconds: 4000), reason: '상한');
      expect(gap(20, s72), const Duration(milliseconds: 3600));
      expect(
        gap(5, const Duration(seconds: 1)),
        const Duration(milliseconds: 600),
        reason: '하한',
      );
      expect(
        gap(5, const Duration(seconds: -3)),
        const Duration(milliseconds: 600),
        reason: '늦어짐',
      );
      expect(gap(5, null), const Duration(milliseconds: 600), reason: '모름');
      expect(gap(21, s72), const Duration(milliseconds: 300), reason: '큐 밀림');
      expect(gap(5, s72, draining: true), const Duration(milliseconds: 40));
    });

    testWidgets('실제 묶음 간격을 재서 카드를 다음 묶음까지 고르게 나눈다', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var now = DateTime(2026, 11, 5, 12);
      final status = SyncStatus(now: () => now)..begin(100);
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisScreen(status: status, onHome: () {}),
        ),
      );
      now = now.add(const Duration(seconds: 32));
      feed(status, 8); // 묶음 평균 32초 → 8장이면 4000ms 간격
      await tester.pump();
      expect(cards(tester), hasLength(1));
      await tester.pump(const Duration(milliseconds: 3900));
      expect(queued(tester), 7, reason: '4초 전에는 다음 장을 꺼내지 않는다');
      await tester.pump(const Duration(milliseconds: 200));
      expect(queued(tester), 6);
    });

    test('ETA: 느린 묶음이 와도 늘지 않고, 시간이 지나면 줄어든다', () {
      var now = DateTime(2026, 11, 5, 12);
      final status = SyncStatus(now: () => now)..begin(100);
      now = now.add(const Duration(minutes: 1));
      status.advance(20); // 20장 1분 → 80장 4분
      expect(status.eta, const Duration(minutes: 4));

      now = now.add(const Duration(seconds: 30));
      expect(status.eta, const Duration(minutes: 3, seconds: 30));

      now = now.add(const Duration(minutes: 9, seconds: 30));
      status.advance(20); // 아주 느린 묶음: 계산값은 커지지만 표시는 그대로
      expect(status.eta, const Duration(minutes: 3, seconds: 30));
    });

    test('ETA는 최근 3묶음만 본다', () {
      var now = DateTime(2026, 11, 5, 12);
      final status = SyncStatus(now: () => now)..begin(1000);
      now = now.add(const Duration(hours: 1));
      status.advance(10); // 아주 느린 첫 묶음
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 10));
        status.advance(10); // 장당 1초
      }
      expect(
        status.eta,
        const Duration(seconds: 960),
        reason: '첫 묶음은 평균에서 빠진다',
      );
    });

    testWidgets('간격이 카드 수명보다 길어도 스테이지가 비지 않는다(큐가 남아 있을 때도 빈 카드)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var now = DateTime(2026, 11, 5, 12);
      final status = SyncStatus(now: () => now)..begin(100);
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisScreen(status: status, onHome: () {}),
        ),
      );
      now = now.add(const Duration(seconds: 32));
      feed(status, 8); // 4000ms 간격, 카드 수명 1140ms
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          cards(tester).length + find.byType(DrawerIdleCard).evaluate().length,
          greaterThan(0),
          reason: '${i * 100}ms',
        );
      }
      expect(queued(tester), greaterThan(0), reason: '큐가 남은 상태에서 확인');
    });

    testWidgets('큐가 비면 빈 카드가 숨 쉬고, 카드가 오면 사라진다', (tester) async {
      final status = await mount(tester);
      await tester.pump();
      final idle = find.byType(DrawerIdleCard);
      expect(idle, findsOneWidget);
      final scale = find.ancestor(
        of: idle,
        matching: find.byType(ScaleTransition),
      );
      await tester.pump(const Duration(milliseconds: 800));
      final a = tester.widget<ScaleTransition>(scale.first).scale.value;
      await tester.pump(const Duration(milliseconds: 800));
      final b = tester.widget<ScaleTransition>(scale.first).scale.value;
      expect((a - b).abs(), closeTo(0.02, 0.001));

      feed(status, 1);
      await tester.pump();
      expect(idle, findsNothing);
    });

    testWidgets('모션 줄이기: 빈 카드는 멈춰 있고 막대도 없다', (tester) async {
      await mount(tester, reduced: true);
      await tester.pumpAndSettle(); // 움직이는 게 없어야 끝난다
      expect(find.byType(DrawerIdleCard), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    test('착지: 비행 85%면 투명하다', () {
      expect(flightOpacity(0.5), 1);
      expect(flightOpacity(0.85), 0);
      expect(flightOpacity(1), 0);
    });

    testWidgets('착지: 보이는 동안 카드가 칸 숫자를 덮지 않는다', (tester) async {
      final status = await mount(tester);
      feed(status, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 681));
      final number = tester.getRect(binNumber('0').first); // 쇼핑 칸
      var visibleFrames = 0;
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final opacity = find.descendant(
          of: find.byType(DrawerFlightCard),
          matching: find.byType(Opacity),
        );
        if (opacity.evaluate().isEmpty) break;
        if (tester.widget<Opacity>(opacity.first).opacity > 0) {
          visibleFrames++;
          expect(
            tester.getRect(opacity.first).bottom,
            lessThanOrEqualTo(number.top + 1),
          );
        }
      }
      expect(visibleFrames, greaterThan(0));
    });
  });

  testWidgets('칸 이름은 "문화"로 줄이고 카드 이름표는 그대로, 글자는 11px 이상이다', (tester) async {
    final status = await mount(tester, size: const Size(360, 640));
    status.count(Category.entertainment, assetId: 'a0');
    status.advance(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('문화'), findsOneWidget);
    expect(find.text('문화생활'), findsOneWidget, reason: '카드 이름표');
    final label = tester.widget<Text>(find.text('문화'));
    final scale =
        tester.getSize(find.text('문화')).height /
        tester.renderObject<RenderBox>(find.text('문화')).size.height;
    expect(label.style!.fontSize! * scale, greaterThanOrEqualTo(11));
    await flush(tester);
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
      await flush(tester);

      final labels = [
        for (final c in Category.values)
          tester.getRect(find.text(drawerBinLabel(c))),
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
