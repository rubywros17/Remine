import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/screens/sync_gate.dart';
import 'package:remine/widgets/sync_banner.dart';

import 'support/fake_device.dart';
import 'support/fake_push.dart';
import 'support/fake_remote.dart';

/// 디버그 `--dart-define=AUTO_SYNC=false`: 저절로 도는 동기화만 끄고, 수동 실행·서버 조회·토큰·재등록은 그대로.
void main() {
  Future<SyncRig> rig(WidgetTester tester, {required bool autoSync}) async =>
      (await tester.runAsync(
        () => SyncRig.create(
          photos: photosNamed({'p0': 'Screenshot_1.png'}),
          texts: {'p0': '캡처 글자 ' * 30},
          push: FakePushClient(),
          autoSync: autoSync,
        ),
      ))!;

  Future<void> settle(WidgetTester tester) async {
    // 동기화는 실제 파일 입출력(OCR 임시 파일)이 있어 진짜 시간으로 몇 번 돌려 준다
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Widget gate(SyncRig r) => MaterialApp(
    home: SyncGate(
      remote: r.remote,
      settings: r.settings,
      child: Scaffold(
        body: Column(
          children: [
            const Text('HOME'),
            SyncBanner(remote: r.remote),
          ],
        ),
      ),
    ),
  );

  testWidgets('꺼져 있으면 앱을 열거나 다시 앞으로 와도 OCR·전송을 안 하고, 첫 분석 화면 없이 홈 + 작은 안내', (
    tester,
  ) async {
    final r = await rig(tester, autoSync: false);
    await tester.pumpWidget(gate(r));
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(r.client.analyzeCalls, isEmpty);
    expect(r.ocr.recognized, isEmpty);
    expect(find.byType(AnalysisScreen), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('자동 정리 꺼짐(디버그)'), findsOneWidget);
  });

  testWidgets('켜져 있으면(기본) 지금처럼 바로 동기화하고 안내는 없다', (tester) async {
    final r = await rig(tester, autoSync: true);
    await tester.pumpWidget(gate(r));
    await settle(tester);

    expect(r.client.analyzeCalls, hasLength(1));
    expect(find.text('자동 정리 꺼짐(디버그)'), findsNothing);
  });

  testWidgets('꺼져 있어도 디버그 화면 [지금 동기화]는 실제로 보낸다', (tester) async {
    final r = await rig(tester, autoSync: false);
    await tester.pumpWidget(
      MaterialApp(
        home: DebugOcrScreen(
          services: fakeServices(r.reader, remote: r.remote),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('지금 동기화'));
    await settle(tester);

    expect(r.client.analyzeCalls, hasLength(1));
    expect(find.textContaining('동기화 끝'), findsWidgets);
  });

  test('꺼져 있으면 기기 재등록은 하지만 저절로 다시 보내지는 않는다', () async {
    final r = await SyncRig.create(
      photos: photosNamed({'p0': 'Screenshot_1.png'}),
      texts: {'p0': '캡처 글자 ' * 30},
      autoSync: false,
      client: RecordingClient(
        responder: (req) => req.path == '/api/interests'
            ? jsonResponse({'code': 'DEVICE_NOT_FOUND'}, 404)
            : RecordingClient().defaultFor(req),
      ),
    );
    await r.state.setDeviceId(3);

    await expectLater(r.repository.interests(), completes);

    expect(
      r.client.sent.where(
        (q) => q.method == 'POST' && q.path == '/api/devices',
      ),
      isNotEmpty,
      reason: '재등록은 그대로',
    );
    expect(r.client.analyzeCalls, isEmpty, reason: '재전송은 자동 실행이라 꺼짐');
  });
}
