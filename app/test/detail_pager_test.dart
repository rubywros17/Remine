import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/widgets/small_widgets.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

/// 상세(좌우 넘기기·위치 표시·아래로 닫기·그리드 복귀)를 확인하는 테스트.
/// 쇼핑 6장의 최신순 id: 5(이어폰) 6(캠핑) 1 2 3 4(가디건 ×4, 가장 오래됨).
Future<FakeScreenshotRepository> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = FakeScreenshotRepository(now: () => _now);
  await tester.pumpWidget(RemineApp(repository: repo, now: () => _now));
  await tester.pumpAndSettle();
  return repo;
}

Finder get _pager => find.byType(PageView);

/// 상세의 현재 페이지 이미지 카드(Hero는 현재 페이지에만 있다).
Finder get _card => find.descendant(of: _pager, matching: find.byType(Hero));

Future<void> _openShoppingDetail(WidgetTester tester, {int tile = 0}) async {
  await tester.ensureVisible(find.text('쇼핑')); // 낮은 화면에서는 스크롤해야 보인다
  await tester.pumpAndSettle();
  await tester.tap(find.text('쇼핑'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Hero).at(tile));
  await tester.pumpAndSettle();
}

Future<void> _swipeLeft(WidgetTester tester) async {
  await tester.fling(_pager, const Offset(-300, 0), 1500);
  await tester.pumpAndSettle();
}

Future<void> _swipeRight(WidgetTester tester) async {
  await tester.fling(_pager, const Offset(300, 0), 1500);
  await tester.pumpAndSettle();
}

void main() {
  group('좌우 넘기기', () {
    testWidgets('위치 표시가 바뀌고 정보 카드가 페이지에 맞춰 갱신된다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);

      await _swipeLeft(tester);
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.text('캠핑 의자 할인 정보'), findsOneWidget);

      await _swipeRight(tester);
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);
    });

    testWidgets('첫 장에서 오른쪽, 마지막 장에서 왼쪽으로 넘겨도 멈춘다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await _swipeRight(tester);
      expect(find.text('1 / 6'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await _swipeLeft(tester);
      }
      expect(find.text('6 / 6'), findsOneWidget);
      await _swipeLeft(tester);
      expect(find.text('6 / 6'), findsOneWidget);
    });

    testWidgets('태그 필터로 들어오면 그 결과 안에서만 이동한다', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('#니트가디건')); // 홈 관심사 카드 → 쇼핑(태그 선택, 4장)
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Hero).first);
      await tester.pumpAndSettle();

      expect(find.text('1 / 4'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await _swipeLeft(tester);
      }
      expect(find.text('4 / 4'), findsOneWidget);
      await _swipeLeft(tester);
      expect(find.text('4 / 4'), findsOneWidget); // 이어폰·캠핑 의자로 넘어가지 않는다
    });

    testWidgets('그리드에서 중간 타일을 열면 그 위치에서 시작한다', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('쇼핑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tile-1'))); // 최신순 세 번째(id 1)
      await tester.pumpAndSettle();

      expect(find.text('3 / 6'), findsOneWidget);
    });
  });

  group('아래로 쓸어 닫기', () {
    testWidgets('기준 거리 이상 끌면 그리드로 돌아간다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await tester.drag(_card, const Offset(0, 260));
      await tester.pumpAndSettle();

      expect(find.text('1 / 6'), findsNothing); // 상세가 닫혔다
      expect(find.text('쇼핑'), findsOneWidget); // 그리드의 큰 제목
    });

    testWidgets('기준 전에 놓으면 스프링으로 제자리에 돌아오고 닫히지 않는다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);
      final before = tester.getCenter(_card);

      final gesture = await tester.startGesture(before);
      await gesture.moveBy(
        const Offset(0, kTouchSlop + 2),
      ); // 터치 슬롭(드래그로 인식되는 최소 거리)
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(
        tester.getCenter(_card).dy,
        greaterThan(before.dy + 30),
      ); // 손가락을 따라 내려갔다
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('1 / 6'), findsOneWidget);
      expect(tester.getCenter(_card).dy, closeTo(before.dy, 1));
    });

    testWidgets('빠르게 쓸어내리면(플링) 거리가 짧아도 닫힌다', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await tester.fling(_card, const Offset(0, 90), 2000);
      await tester.pumpAndSettle();

      expect(find.text('1 / 6'), findsNothing);
    });
  });

  group('그리드 복귀', () {
    testWidgets('낮은 화면에서도 마지막으로 본 항목의 타일이 보인다', (tester) async {
      await _pumpApp(tester, size: const Size(390, 520));
      await _openShoppingDetail(tester);
      for (var i = 0; i < 5; i++) {
        await _swipeLeft(tester);
      }
      expect(find.text('6 / 6'), findsOneWidget);

      await tester.tap(find.byType(BackButtonCircle));
      await tester.pumpAndSettle();

      // 마지막 장(id 4)의 타일이 화면 안에 있다
      final rect = tester.getRect(find.byKey(const ValueKey('tile-4')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(520));
    });

    testWidgets('카테고리를 바꿔도 상세에서는 유지되고 돌아가면 그리드에 반영된다', (tester) async {
      final repo = await _pumpApp(tester);
      await _openShoppingDetail(tester);

      await tester.tap(find.byKey(const ValueKey('category-chip-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('장소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 서랍으로 옮기기'));
      await tester.pumpAndSettle();

      // 상세: 같은 항목이 그대로 보이고 칩만 장소로 바뀐다
      expect(find.text('1 / 6'), findsOneWidget);
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);
      expect(find.widgetWithText(AppChip, '장소'), findsOneWidget);
      expect((await repo.summary()).of(Category.shopping).count, 5);

      // 그리드: 돌아가면 5장
      await tester.tap(find.byType(BackButtonCircle));
      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsNWidgets(5));
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('레이아웃', () {
    testWidgets('이미지 카드가 남는 세로 공간의 가운데에 놓인다(위·아래 여백이 비슷하다)', (tester) async {
      await _pumpApp(tester);
      await _openShoppingDetail(tester);

      final card = tester.getRect(_card);
      final info = tester.getRect(find.byKey(const ValueKey('info-card-5')));
      const topBarBottom = 56.0;
      final gapAbove = card.top - topBarBottom;
      final gapBelow = info.top - card.bottom;

      expect(gapBelow, greaterThan(0));
      expect((gapAbove - gapBelow).abs(), lessThan(28));
    });
  });
}
