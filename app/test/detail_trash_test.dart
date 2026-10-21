import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/screens/detail_screen.dart' show trashSemanticsAction;

final _now = DateTime(2026, 10, 19, 12, 0);

/// 위로 던져 휴지통으로 보내는 시그니처 모션. 쇼핑 6장(최신순 id): 5(이어폰) 6(캠핑) 1 2 3 4.
/// 화면 높이 844 → 기준선(1/3) ≈ 281px.
late List<String> _haptics;

Future<FakeScreenshotRepository> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // 햅틱 호출을 가로채 센다(플랫폼 채널 모의).
  _haptics = [];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        _haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final repo = FakeScreenshotRepository(now: () => _now);
  await tester.pumpWidget(RemineApp(repository: repo, now: () => _now));
  await tester.pumpAndSettle();
  return repo;
}

Finder get _pager => find.byType(PageView);
Finder get _card => find.descendant(of: _pager, matching: find.byType(Hero));
Finder get _trashTarget => find.byKey(const ValueKey('trash-target'));

Future<void> _openShoppingDetail(WidgetTester tester) async {
  await tester.tap(find.text('쇼핑'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Hero).first);
  await tester.pumpAndSettle();
}

/// 카드를 잡고 위로 [dy]만큼 끈 상태(손은 떼지 않음)로 돌려준다.
Future<TestGesture> _dragUp(WidgetTester tester, double dy) async {
  final g = await tester.startGesture(tester.getCenter(_card));
  await g.moveBy(const Offset(0, -(kTouchSlop + 2))); // 터치 슬롭을 넘겨 드래그를 시작
  await g.moveBy(Offset(0, -dy));
  await tester.pump();
  return g;
}

Future<void> _swipeLeft(WidgetTester tester) async {
  await tester.fling(_pager, const Offset(-300, 0), 1500);
  await tester.pumpAndSettle();
}

Color _trashTargetColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(_trashTarget);
  return (box.decoration as BoxDecoration).color!;
}

Color _trashIconColor(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(of: _trashTarget, matching: find.byType(Icon)),
    )
    .color!;

void main() {
  group('끄는 동안', () {
    testWidgets('카드가 손가락을 따라 올라가며 줄어들고, 휴지통 아이콘이 나타나 끌수록 커진다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);
      final before = tester.getRect(_card);
      expect(_trashTarget, findsNothing); // 끌기 전에는 보이지 않는다

      final g = await _dragUp(tester, 100);
      final mid = tester.getRect(_card);
      final iconMid = tester.getSize(_trashTarget);
      expect(mid.center.dy, lessThan(before.center.dy - 60)); // 올라갔다
      expect(mid.width, lessThan(before.width)); // 줄어들었다
      expect(_trashTarget, findsOneWidget);

      await g.moveBy(const Offset(0, -120));
      await tester.pump();
      final high = tester.getRect(_card);
      expect(high.center.dy, lessThan(mid.center.dy - 60));
      // 아이콘도 커진다(Transform으로 그려진 실제 크기)
      expect(tester.getRect(_trashTarget).width, greaterThan(iconMid.width));

      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('기준선 전에 놓으면 스프링으로 복귀하고 아무것도 버려지지 않는다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);
      final before = tester.getRect(_card);

      final g = await _dragUp(tester, 150); // 기준선(≈281) 전
      await g.up();
      await tester.pumpAndSettle();

      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);
      expect(repo.trashedIds, isEmpty);
      expect(_trashTarget, findsNothing);
      final after = tester.getRect(_card);
      expect(after.center.dy, closeTo(before.center.dy, 1));
      expect(after.width, closeTo(before.width, 1));
      expect(_haptics, isEmpty);
    });

    testWidgets('기준선을 넘는 순간 아이콘이 강조되고 햅틱이 한 번 울린다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      final g = await _dragUp(tester, 200);
      expect(_trashTargetColor(tester), AppColors.white); // 아직 기준선 전
      expect(_trashIconColor(tester), AppColors.ink);
      expect(_haptics, isEmpty);

      await g.moveBy(const Offset(0, -120)); // 기준선 통과
      await tester.pump();
      expect(_trashTargetColor(tester), AppColors.trashActiveBackground); // 강조
      expect(_trashIconColor(tester), AppColors.lemon);
      expect(_haptics, ['HapticFeedbackType.mediumImpact']);

      await g.moveBy(const Offset(0, -40)); // 더 올려도 다시 울리지 않는다
      await tester.pump();
      expect(_haptics.length, 1);

      await g.moveBy(const Offset(0, 200)); // 기준선 아래로 되돌아가면 강조 해제
      await tester.pump();
      expect(_trashTargetColor(tester), AppColors.white);
      await g.moveBy(const Offset(0, -200)); // 다시 통과하면 한 번 더
      await tester.pump();
      expect(_haptics.length, 2);

      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group('던지기', () {
    testWidgets('기준선을 넘겨 놓으면 휴지통으로 가고 다음 항목이 보이며, 되돌리기로 복원된다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      final g = await _dragUp(tester, 330);
      await g.up();
      // 스낵바는 4초 뒤 사라지므로 pumpAndSettle로 끝까지 가지 않고, 모션이 끝날 만큼만 진행한다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      // 휴지통으로 이동, 같은 자리에 다음 항목
      expect(repo.trashedIds, {5});
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('캠핑 의자 할인 정보'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsNothing);
      expect(_trashTarget, findsNothing);
      // 안내 + 되돌리기
      expect(find.text('휴지통으로 옮겼어'), findsOneWidget);
      expect(find.text('되돌리기'), findsOneWidget);

      await tester.pump(
        const Duration(milliseconds: 500),
      ); // 스낵바가 올라오는 모션이 끝나야 눌린다
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();

      expect(repo.trashedIds, isEmpty);
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);
    });

    testWidgets('거리가 짧아도 빠르게 던지면(플링) 휴지통으로 간다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await tester.fling(_card, const Offset(0, -120), 3000);
      await tester.pumpAndSettle();

      expect(repo.trashedIds, {5});
      expect(find.text('1 / 5'), findsOneWidget);
    });

    testWidgets('빠르더라도 거의 움직이지 않은 스침은 무시한다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await tester.fling(_card, const Offset(0, -(kTouchSlop + 4)), 3000);
      await tester.pumpAndSettle();

      expect(repo.trashedIds, isEmpty);
      expect(find.text('1 / 6'), findsOneWidget);
    });

    testWidgets('마지막 장을 버리면 이전 장으로 간다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);
      for (var i = 0; i < 5; i++) {
        await _swipeLeft(tester);
      }
      expect(find.text('6 / 6'), findsOneWidget);

      final g = await _dragUp(tester, 330);
      await g.up();
      await tester.pumpAndSettle();

      expect(repo.trashedIds, {4});
      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('가디건 후기만 모아 본 페이지'), findsOneWidget); // 이전 장(id 3)
    });

    testWidgets('목록이 비면 그리드로 돌아가고, 되돌리기가 그리드에 반영된다', (tester) async {
      final repo = await _pumpApp(tester);
      await tester.tap(find.text('쇼핑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('#이어폰'));
      await tester.tap(find.text('#이어폰')); // 이 태그는 1장뿐
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Hero).first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);

      final g = await _dragUp(tester, 330);
      await g.up();
      await tester.pumpAndSettle();

      expect(repo.trashedIds, {5});
      expect(find.text('1 / 1'), findsNothing); // 상세가 닫혔다
      expect(find.text('아직 여기엔 아무것도 없어'), findsOneWidget); // 그리드(이어폰 태그)는 비었다
      expect(find.text('되돌리기'), findsOneWidget);

      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();

      expect(repo.trashedIds, isEmpty);
      expect(find.text('아직 여기엔 아무것도 없어'), findsNothing);
      expect(find.byType(Hero), findsOneWidget); // 복원된 한 장
    });
  });

  group('화면 읽기 전용 동작(보이는 메뉴 없음)', () {
    /// 이미지 카드의 "휴지통으로 옮기기" 동작을 접근성 트리로 실행한다(스크린 리더가 하는 것과 같다).
    void performTrashAction(WidgetTester tester) {
      final node = tester.getSemantics(find.bySemanticsLabel('캡처 이미지'));
      final id = CustomSemanticsAction.getIdentifier(trashSemanticsAction);
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        contains(id),
        reason: '이미지 카드에 동작이 없다',
      );
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
    }

    testWidgets('정보 카드에 ⋯ 메뉴·휴지통 버튼이 없다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      expect(find.byIcon(LucideIcons.ellipsis), findsNothing);
      expect(find.byKey(const ValueKey('more-menu-5')), findsNothing);
      expect(find.byTooltip('더 보기 메뉴'), findsNothing);
      expect(find.bySemanticsLabel('더 보기 메뉴'), findsNothing);
      expect(find.text('휴지통으로'), findsNothing);
      handle.dispose();
    });

    testWidgets('동작 "휴지통으로 옮기기"는 던지기와 같은 결과다', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      performTrashAction(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(repo.trashedIds, {5});
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('휴지통으로 옮겼어'), findsOneWidget);
      handle.dispose();
    });
  });

  group('애니메이션 줄이기', () {
    void reduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    testWidgets('끄는 동안 효과가 없고, 기준선을 넘겨 놓으면 바로 처리된다', (tester) async {
      reduceMotion(tester);
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);
      final before = tester.getRect(_card);

      final g = await _dragUp(tester, 330);
      expect(tester.getRect(_card), before); // 카드는 움직이지 않는다
      expect(_trashTarget, findsNothing); // 휴지통 아이콘도 없다
      expect(_haptics, isEmpty);
      await g.up();
      await tester.pump();
      await tester.pump();

      expect(repo.trashedIds, {5});
      expect(find.text('1 / 5'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0); // 진행 중인 애니메이션이 없다
    });

    testWidgets('화면 읽기 동작도 바로 처리된다', (tester) async {
      reduceMotion(tester);
      final handle = tester.ensureSemantics();
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      final node = tester.getSemantics(find.bySemanticsLabel('캡처 이미지'));
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(trashSemanticsAction),
      );
      await tester.pump();
      await tester.pump();

      expect(repo.trashedIds, {5});
      expect(find.text('1 / 5'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      handle.dispose();
    });
  });
}
