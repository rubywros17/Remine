import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/widgets/sync_banner.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

Future<SyncRig> _rig(WidgetTester tester) async => (await tester.runAsync(
  () => SyncRig.create(
    photos: fakePhotos(1),
    texts: {'p0': '글자'},
    client: RecordingClient()..throwOnSend = const SocketException('x'),
  ),
))!;

Future<void> _show(
  WidgetTester tester,
  SyncRig rig, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(children: [SyncBanner(remote: rig.remote)]),
      ),
    ),
  );
}

void main() {
  testWidgets('연결 실패는 한 줄로 짧게 "서버에 연결하지 못했어요 · 다시 시도"이고 낮다', (tester) async {
    final rig = await _rig(tester);
    rig.status.finish(issue: SyncIssue.offline);
    await _show(tester, rig);

    expect(find.text('서버에 연결하지 못했어요 · 다시 시도'), findsOneWidget);
    final text = tester.widget<Text>(find.text('서버에 연결하지 못했어요 · 다시 시도'));
    expect(text.maxLines, 1);
    // 배너 높이(위 여백 8 포함)는 한 줄짜리라 예전 두 줄 안내(약 70px)보다 훨씬 낮다.
    expect(
      tester.getSize(find.byType(SyncBanner)).height,
      lessThanOrEqualTo(8 + 40),
    );
    final deco =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(SyncBanner),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(deco.color, AppColors.lemon);
  });

  testWidgets('서버 오류·일부 실패도 한 줄이다', (tester) async {
    final rig = await _rig(tester);
    rig.status.finish(issue: SyncIssue.server);
    await _show(tester, rig);
    expect(find.text('서버가 불안정해요 · 다시 시도'), findsOneWidget);

    rig.status.finish(issue: SyncIssue.partial, failedCount: 288);
    await tester.pump();
    expect(find.text('288장은 다음에 다시 분류해요 · 다시 시도'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SyncBanner)).height,
      lessThanOrEqualTo(48),
    );
  });

  testWidgets('아주 좁은 화면에서도 넘치지 않고 말줄임으로 한 줄을 지킨다', (tester) async {
    final rig = await _rig(tester);
    rig.status.finish(issue: SyncIssue.partial, failedCount: 288);
    await _show(tester, rig, width: 240);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(SyncBanner)).height,
      lessThanOrEqualTo(48),
    );
  });

  testWidgets('누르면 다시 시도한다', (tester) async {
    final rig = await _rig(tester);
    rig.status.finish(issue: SyncIssue.offline);
    await _show(tester, rig);
    final before = rig.client.sent.length;

    await tester.tap(find.byType(SyncBanner));
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));

    expect(rig.client.sent.length, greaterThan(before));
  });

  testWidgets('문제가 없으면 아무것도 그리지 않는다', (tester) async {
    final rig = await _rig(tester);
    await _show(tester, rig);

    expect(find.byType(DecoratedBox), findsNothing);
  });
}
