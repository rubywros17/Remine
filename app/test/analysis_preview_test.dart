import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/screens/analysis_preview_screen.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/widgets/wordmark.dart';

import 'support/fake_device.dart';

/// 디버그 전용 첫 분석 미리보기: 가짜 진행만 돌고, 끝나면 완료 상태 → 닫기.
void main() {
  // 미리보기 타이머가 도는 동안은 pumpAndSettle이 끝까지(20초) 돌아서, 화면 전환만 끝낸다.
  // 첫 pump는 전환 시작 프레임이라 두 번 필요하다.
  Future<void> finishRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openFrom(WidgetTester tester, RemineApp app) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(Wordmark).first);
    await finishRoute(tester);
  }

  testWidgets('가짜 데이터 모드: 약 20초에 300장까지 오르고 완료 상태에서 닫힌다', (tester) async {
    await openFrom(tester, const RemineApp());
    expect(find.byType(AnalysisPreviewScreen), findsOneWidget);

    final status = tester
        .widget<AnalysisScreen>(find.byType(AnalysisScreen))
        .status!;
    await tester.pump(const Duration(seconds: 10));
    expect(status.done, inInclusiveRange(100, 200));
    expect(status.counts.values.reduce((a, b) => a + b), status.done);
    expect(find.text('홈에서 먼저 볼래요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    expect(status.finished, isTrue);
    await tester.pumpAndSettle(); // 남은 큐를 칸에 채운다
    expect(status.counts.values.reduce((a, b) => a + b), 300);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('장 정리했어요'), findsOneWidget);

    await tester.tap(find.text('홈에서 둘러보기'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisPreviewScreen), findsNothing);
  });

  testWidgets('기기 모드: 디버그 화면 버튼으로 열고, 진행 중에 닫아도 타이머가 남지 않는다', (tester) async {
    await openFrom(
      tester,
      RemineApp(device: fakeServices(FakeGalleryReader())),
    );
    final button = find.text('첫 분석 화면 미리보기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await finishRoute(tester);
    expect(find.byType(AnalysisPreviewScreen), findsOneWidget);

    await tester.tap(find.text('홈에서 먼저 볼래요'));
    await finishRoute(tester);
    expect(find.byType(AnalysisPreviewScreen), findsNothing);
  });
}
