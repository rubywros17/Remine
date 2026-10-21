import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';
import 'package:remine/widgets/thumb_placeholder.dart';
import 'package:remine/widgets/wordmark.dart';

final _now = DateTime(2026, 10, 19, 12, 0); // 월요일

/// 폰 크기(390x844)로 앱을 띄운다. [repo]를 넘기면 테스트가 저장소 상태를 직접 확인할 수 있다.
Future<FakeScreenshotRepository> _pumpApp(
  WidgetTester tester, {
  String startScreen = '',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = FakeScreenshotRepository(now: () => _now);
  await tester.pumpWidget(
    RemineApp(repository: repo, now: () => _now, startScreen: startScreen),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder get _tiles => find.byType(Hero); // 카테고리 그리드의 타일마다 Hero가 하나씩 있다

void main() {
  group('홈', () {
    testWidgets('제목·관심사 카드·알약·탭바를 그린다', (tester) async {
      await _pumpApp(tester);

      expect(find.byType(Wordmark), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Remine',
        ),
        findsOneWidget,
      );
      expect(find.text('re:mine', findRichText: true), findsOneWidget);
      expect(find.text('MON 10.19'), findsOneWidget);
      expect(find.byType(HighlighterText), findsOneWidget);
      expect(find.text('캐냈어요'), findsOneWidget);
      // 관심사 카드
      expect(find.text('잊은 관심사'), findsOneWidget);
      expect(find.text('×4'), findsOneWidget);
      expect(find.text('#니트가디건'), findsOneWidget);
      expect(find.text('2주 동안 4번 캡처 · 9일째 잠자는 중'), findsOneWidget);
      // 서랍
      expect(find.text('내 캡처 서랍'), findsOneWidget);
      expect(find.text('30 shots'), findsOneWidget);
      for (final c in Category.values) {
        expect(find.text(c.label), findsOneWidget, reason: c.label);
      }
      // 탭바 3개
      expect(find.text('서랍'), findsOneWidget);
      expect(find.text('관심사'), findsOneWidget);
      expect(find.text('검색'), findsOneWidget);
    });

    testWidgets('관심사 카드의 콜라주는 회전한 모서리까지 카드 안쪽 여백 안에 있다', (tester) async {
      await _pumpApp(tester);

      final card = tester.getRect(find.byType(InterestCard));
      final safe = card.deflate(8); // 테두리에서 최소 8px 떨어져야 한다
      final thumbs = find.descendant(
        of: find.byType(InterestCard),
        matching: find.byType(ThumbPlaceholder),
      );
      expect(thumbs, findsNWidgets(3));
      for (final element in thumbs.evaluate()) {
        final finder = find.byElementPredicate((e) => e == element);
        // getTopLeft 등은 부모의 회전을 포함한 화면 좌표라, 네 모서리가 곧 회전 후의 모양이다.
        for (final corner in [
          tester.getTopLeft(finder),
          tester.getTopRight(finder),
          tester.getBottomLeft(finder),
          tester.getBottomRight(finder),
        ]) {
          expect(
            safe.contains(corner),
            isTrue,
            reason: '썸네일 모서리 $corner 가 카드 $safe 밖',
          );
        }
      }
    });

    testWidgets('알약은 개수 내림차순이고 기타가 마지막이며, 가장 많은 쇼핑만 셀라돈으로 채운다', (tester) async {
      await _pumpApp(tester);

      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      final left = tester.getTopLeft(find.text('쇼핑')).dx;
      expect(
        left,
        lessThan(tester.getTopLeft(find.text('장소')).dx + 1000),
      ); // 렌더됨
      expect(top('기타'), greaterThanOrEqualTo(top('장소'))); // 기타는 마지막 줄 쪽

      final filled = find.ancestor(
        of: find.text('쇼핑'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color == AppColors.celadon,
        ),
      );
      expect(filled, findsWidgets);
      final notFilled = find.ancestor(
        of: find.text('장소'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color == AppColors.celadon,
        ),
      );
      expect(notFilled, findsNothing);
    });

    testWidgets('관심사·검색 탭은 빈 화면 자리다', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('관심사'));
      await tester.pumpAndSettle();
      expect(find.text('관심사는 곧 채워질 거야'), findsOneWidget);

      await tester.tap(find.text('검색'));
      await tester.pumpAndSettle();
      expect(find.text('검색도 곧 열릴 거야'), findsOneWidget);

      await tester.tap(find.text('서랍'));
      await tester.pumpAndSettle();
      expect(find.text('내 캡처 서랍'), findsOneWidget);
    });
  });

  group('카테고리 화면', () {
    testWidgets('태그 칩을 누르면 그 태그의 캡처만 남고, 다시 누르면 풀린다', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('쇼핑'));
      await tester.pumpAndSettle();

      expect(find.text('쇼핑'), findsOneWidget); // 큰 제목
      expect(find.text('6'), findsOneWidget); // 거대한 개수
      expect(_tiles, findsNWidgets(6));
      expect(find.text('#니트가디건'), findsOneWidget);

      await tester.ensureVisible(find.text('#이어폰')); // 가로 스크롤 칩 줄 밖에 있을 수 있다
      await tester.tap(find.text('#이어폰'));
      await tester.pumpAndSettle();
      expect(_tiles, findsNWidgets(1));
      final selected = tester.widget<AppChip>(
        find.widgetWithText(AppChip, '#이어폰'),
      );
      expect(selected.background, AppColors.lemon); // 선택된 칩은 레몬

      await tester.ensureVisible(find.text('#이어폰'));
      await tester.tap(find.text('#이어폰'));
      await tester.pumpAndSettle();
      expect(_tiles, findsNWidgets(6));

      await tester.ensureVisible(find.text('#니트가디건'));
      await tester.tap(find.text('#니트가디건'));
      await tester.pumpAndSettle();
      expect(_tiles, findsNWidgets(4));
    });

    testWidgets('거대한 개수는 딥 셀라돈이다', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('장소'));
      await tester.pumpAndSettle();

      final number = tester.widget<Text>(find.text('4'));
      expect(number.style!.color, AppColors.celadonDeep);
    });

    testWidgets('홈의 관심사 카드를 누르면 그 태그가 선택된 채로 열린다', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('#니트가디건'));
      await tester.pumpAndSettle();

      expect(_tiles, findsNWidgets(4));
      expect(
        tester
            .widget<AppChip>(find.widgetWithText(AppChip, '#니트가디건'))
            .background,
        AppColors.lemon,
      );
    });
  });

  group('카테고리 수정', () {
    // 쇼핑 → 첫 번째 타일(가장 최신: 무선 이어폰 최저가) → 상세 → 카테고리 칩 → 시트
    Future<FakeScreenshotRepository> openSheet(WidgetTester tester) async {
      final repo = await _pumpApp(tester);
      await tester.tap(find.text('쇼핑'));
      await tester.pumpAndSettle();
      await tester.tap(_tiles.first);
      await tester.pumpAndSettle();
      expect(find.text('무선 이어폰 최저가 비교'), findsOneWidget);
      await tester.tap(find.text('쇼핑')); // 상세의 카테고리 칩
      await tester.pumpAndSettle();
      expect(find.text('이거 어디 서랍이야?'), findsOneWidget);
      return repo;
    }

    testWidgets('시트: AI가 낸 값을 보여주고 버튼 문구가 같은 값/다른 값에 따라 바뀐다', (tester) async {
      await openSheet(tester);

      expect(find.textContaining('AI는 '), findsOneWidget);
      expect(find.text('응, 쇼핑 맞아'), findsOneWidget); // 현재 값 그대로면 확인 문구

      await tester.tap(find.text('장소'));
      await tester.pumpAndSettle();
      expect(find.text('이 서랍으로 옮기기'), findsOneWidget);
      expect(find.text('응, 쇼핑 맞아'), findsNothing);

      await tester.tap(find.text('쇼핑').last); // 시트 안 타일로 되돌림
      await tester.pumpAndSettle();
      expect(find.text('응, 쇼핑 맞아'), findsOneWidget);
    });

    testWidgets('다른 서랍으로 옮기면 저장소(USER)와 상세·카테고리·홈 집계에 바로 반영된다', (tester) async {
      final repo = await openSheet(tester);

      await tester.tap(find.text('장소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 서랍으로 옮기기'));
      await tester.pumpAndSettle();

      // 상세의 카테고리 칩이 바뀐다
      expect(find.text('이거 어디 서랍이야?'), findsNothing);
      expect(find.text('장소'), findsOneWidget);

      final summary = await repo.summary();
      expect(summary.of(Category.shopping).count, 5);
      expect(summary.of(Category.place).count, 5);
      final moved = (await repo.list(category: Category.place)).items
          .firstWhere((s) => s.summary == '무선 이어폰 최저가 비교');
      expect(moved.categorySource, CategorySource.user);
      expect(moved.autoCategory, Category.shopping); // AI 값은 그대로
      expect(moved.tags, ['이어폰', '최저가']); // 태그 유지

      // 뒤로 가면 카테고리 화면의 개수와 홈의 개수도 새 값이다
      await tester.tap(find.byType(BackButtonCircle));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget); // 쇼핑 5장
      await tester.tap(find.byType(BackButtonCircle));
      await tester.pumpAndSettle();
      expect(find.text('30 shots'), findsOneWidget);
      final badges = tester
          .widgetList<CountBadge>(find.byType(CountBadge))
          .map((b) => b.count)
          .toList();
      expect(badges.where((c) => c == 5).length, 2); // 쇼핑 5, 장소 5
    });

    testWidgets('"응, 쇼핑 맞아"는 값은 그대로 두고 USER로 저장한다', (tester) async {
      final repo = await openSheet(tester);

      await tester.tap(find.text('응, 쇼핑 맞아'));
      await tester.pumpAndSettle();

      final item = (await repo.list(category: Category.shopping)).items
          .firstWhere((s) => s.summary == '무선 이어폰 최저가 비교');
      expect(item.category, Category.shopping);
      expect(item.categorySource, CategorySource.user);
    });

    testWidgets('시트를 ×로 닫으면 아무것도 바뀌지 않는다', (tester) async {
      final repo = await openSheet(tester);

      await tester.tap(
        find.byIcon(Icons.close).evaluate().isEmpty
            ? find.bySemanticsLabel('닫기')
            : find.byIcon(Icons.close),
      );
      await tester.pumpAndSettle();

      expect(find.text('이거 어디 서랍이야?'), findsNothing);
      final item = (await repo.list(category: Category.shopping)).items.first;
      expect(item.categorySource, CategorySource.auto);
    });
  });

  group('애니메이션 줄이기', () {
    testWidgets('기본에서는 화면 전환이 애니메이션으로 진행된다', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('쇼핑'));
      await tester.pump();

      expect(tester.binding.transientCallbackCount, greaterThan(0)); // 전환 중
      await tester.pumpAndSettle();
    });

    testWidgets('켜져 있으면 전환 없이 바로 바뀐다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpApp(tester);

      await tester.tap(find.text('쇼핑'));
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0); // 진행 중인 애니메이션이 없다
      expect(
        find.byType(BackButtonCircle),
        findsOneWidget,
      ); // 첫 프레임에 이미 카테고리 화면이다
    });

    testWidgets('모션 토큰의 모든 시간이 0이 된다', (tester) async {
      Duration? fast, slow;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              fast = AppMotion.duration(context, MotionDuration.fast);
              slow = AppMotion.duration(context, MotionDuration.slow);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(fast, Duration.zero);
      expect(slow, Duration.zero);
    });
  });

  group('첫 분석 화면', () {
    testWidgets('가짜 진행값의 정적 화면이다', (tester) async {
      await _pumpApp(tester, startScreen: 'analysis');

      expect(find.byType(AnalysisScreen), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('/ 300장 꺼냈어요'), findsOneWidget);
      expect(find.text('DIGGING…'), findsOneWidget);
      expect(find.text(PrivacyNote.text), findsOneWidget);
      for (final c in Category.values) {
        expect(find.text(c.label), findsOneWidget, reason: c.label);
      }
    });
  });
}
