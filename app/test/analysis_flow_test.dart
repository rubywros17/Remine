import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/privacy/app_rules.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/photo_viewer_screen.dart';
import 'package:remine/screens/sync_gate.dart';
import 'package:remine/widgets/drawer_stage.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

Widget _app(Widget home, {FakeGalleryReader? reader}) {
  final app = MaterialApp(home: home);
  return reader == null
      ? app
      : DeviceScope(services: fakeServices(reader), child: app);
}

void main() {
  group('Remine 자기 캡처 제외', () {
    test('파일명 앱 이름이 Remine이면 대소문자·구두점과 상관없이 자기 캡처다', () {
      for (final name in [
        'Screenshot_20261021_101010_Remine.jpg',
        'Screenshot_20261021_101010_remine.jpg',
        'Screenshot_20261021_101010_REMINE.png',
        'Screenshot_20261021_101010_re:mine.jpg',
      ]) {
        expect(isOwnAppCapture(name), isTrue, reason: name);
      }
      for (final name in [
        'Screenshot_20261021_101010_Reminder.jpg',
        'Screenshot_20261021_101010_Chrome.jpg',
        'Screenshot_1.png',
        'Remine.jpg',
      ]) {
        expect(isOwnAppCapture(name), isFalse, reason: name);
      }
    });

    test('OCR도 전송도 하지 않고 목록(갤러리 읽기)에서도 빠진다', () async {
      final rig = await SyncRig.create(
        photos: photosNamed({
          'own1': 'Screenshot_20261021_101010_Remine.jpg',
          'own2': 'Screenshot_20261021_101011_remine.jpg',
          'ok1': 'Screenshot_20261021_101012_Chrome.jpg',
        }),
        texts: {
          'own1': '우리 앱 화면 SENTINEL',
          'own2': '우리 앱 화면 SENTINEL',
          'ok1': '글자 ' * 60,
        },
      );
      expect((await rig.capture.recent('shots')).map((p) => p.id), [
        'ok1',
      ], reason: 'recent()가 자기 캡처를 뺀다');
      await rig.sync.run();

      expect(rig.ocr.recognized, ['ok1']);
      final body = rig.client.sent.map((r) => r.utf8Text).join();
      expect(body, isNot(contains('own1')));
      expect(body, isNot(contains('own2')));
      expect(body, isNot(contains('SENTINEL')));
      expect(rig.status.done, 1);
    });

    test('capture.run에 직접 들어와도 OCR·저장을 하지 않는다', () async {
      final rig = await SyncRig.create(
        photos: photosNamed({'own1': 'Screenshot_20261021_101010_Remine.jpg'}),
        texts: {'own1': '글자'},
      );
      final run = await rig.capture.run(rig.reader.photos);

      expect(rig.ocr.recognized, isEmpty);
      expect(run.records, isEmpty);
      expect(await rig.capture.store.find('own1'), isNull);
      expect(await rig.capture.verdicts.find('own1'), isNull);
    });
  });

  group('첫 분석 화면', () {
    testWidgets('진행 중: 실제 숫자, 안내 제목, 작은 보안 문구, 홈에서 먼저 보기', (tester) async {
      final status = SyncStatus()..begin(15, intervalMs: 4500);
      status.advance(5);
      for (var i = 0; i < 3; i++) {
        status.count(Category.shopping);
      }
      status.count(Category.place);
      status.count(Category.place);
      await tester.pumpWidget(
        _app(AnalysisScreen(status: status, onHome: () {})),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.text('/ 15장 꺼냈어요'), findsOneWidget);
      expect(find.text('지금까지 찾은 것'), findsNothing);
      for (final c in Category.values) {
        expect(find.text(drawerBinLabel(c)), findsOneWidget, reason: '칸 7개');
      }
      expect(find.text('홈에서 먼저 볼래요'), findsOneWidget);
      expect(find.text('홈으로'), findsNothing);
      expect(find.text(PrivacyNote.text), findsOneWidget);
      expect(find.text(keepScreenOnHint), findsOneWidget);
    });

    testWidgets('끝나면 "N장 꺼냈어요"와 [홈으로]가 나오고 자동으로 넘어가지 않는다', (tester) async {
      var home = 0;
      final status = SyncStatus()..begin(15);
      status.advance(15);
      for (var i = 0; i < 15; i++) {
        status.count(i.isEven ? Category.shopping : Category.info);
      }
      status.finish();
      await tester.pumpWidget(
        _app(AnalysisScreen(status: status, onHome: () => home++)),
      );

      expect(find.text('15'), findsOneWidget);
      expect(find.text('장 꺼냈어요'), findsOneWidget);
      expect(find.text('/ 15장 꺼냈어요'), findsNothing);
      expect(find.bySemanticsLabel('15장 꺼냈어요'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget);
      expect(find.text('홈에서 먼저 볼래요'), findsNothing);
      expect(
        find.text(keepScreenOnHint),
        findsNothing,
        reason: '끝나면 화면 안내도 없다',
      );
      await tester.pump(const Duration(seconds: 5));
      expect(home, 0, reason: '누르기 전에는 이동하지 않는다');

      await tester.tap(find.text('홈으로'));
      expect(home, 1);
    });

    testWidgets('꺼낸 게 없으면(서버에 못 닿음 등) 이유와 함께 알려 준다', (tester) async {
      final status = SyncStatus()..finish(issue: SyncIssue.offline);
      await tester.pumpWidget(
        _app(AnalysisScreen(status: status, onHome: () {})),
      );

      expect(find.text('새로 꺼낼 캡처가 없어요'), findsOneWidget);
      expect(find.textContaining('서버에 연결하지 못했어요'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget);
    });

    testWidgets('카드는 방금 분류된 실제 캡처 썸네일 + 그 카테고리 이름표다', (tester) async {
      final status = SyncStatus()..begin(10);
      await tester.pumpWidget(
        _app(
          AnalysisScreen(status: status, onHome: () {}),
          reader: FakeGalleryReader(),
        ),
      );
      status.count(Category.shopping, assetId: 'a1');
      status.advance(1);
      await tester.pump();
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('쇼핑'), findsNWidgets(2), reason: '칸 이름 + 카드 이름표');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Image), findsNothing, reason: '칸으로 들어가 사라진다');
    });

    test('숨김(민감·금융) 캡처는 썸네일 id 없이 기록된다', () {
      final status = SyncStatus()..begin(1);
      status.count(Category.etc);
      expect(status.shots.single.assetId, isNull);
      expect(status.counts[Category.etc], 1);
    });

    test('분류 기록은 순서대로 전부 남고 새 실행에서 비워진다', () {
      final status = SyncStatus()..begin(10);
      for (var i = 0; i < 6; i++) {
        status.count(Category.info, assetId: 'a$i');
      }
      expect(status.shots.map((s) => s.assetId), [
        'a0',
        'a1',
        'a2',
        'a3',
        'a4',
        'a5',
      ]);
      status.begin(1);
      expect(status.shots, isEmpty);
    });

    test('실행이 끝나면 기록을 비우고, 끝나는 순간의 알림에서는 아직 읽을 수 있다', () {
      final status = SyncStatus()..begin(1);
      status.count(Category.info, assetId: 'a0');
      var seenAtFinish = -1;
      status.addListener(() => seenAtFinish = status.shots.length);
      status.finish();
      expect(seenAtFinish, 1);
      expect(status.shots, isEmpty);
      expect(status.counts[Category.info], 1, reason: '칸 개수는 남는다');
    });
  });

  group('SyncGate', () {
    testWidgets('첫 분석 중에만 화면 꺼짐을 막고, 끝나면 푼다', (tester) async {
      final calls = <bool>[];
      final rig = (await tester.runAsync(
        () => SyncRig.create(
          photos: const [],
          texts: const {},
          client: RecordingClient(
            responder: (r) => Completer<http.StreamedResponse>().future,
          ),
        ),
      ))!;
      await tester.pumpWidget(
        _app(
          SyncGate(
            remote: rig.remote,
            keepScreenOn: calls.add,
            child: const Text('HOME'),
          ),
        ),
      );
      await tester.pump();
      expect(calls, [true]);

      rig.status.finish(); // 완료 화면([홈으로])에서는 풀어 둔다
      await tester.pump();
      expect(calls, [true, false]);
      await tester.pump(const Duration(minutes: 6)); // 응답 없는 요청의 시간 제한을 흘려보낸다
    });

    testWidgets('"홈에서 먼저 볼래요"로 나가면 바로 풀고, 채널이 없어도 예외가 없다', (tester) async {
      final calls = <bool>[];
      final rig = (await tester.runAsync(
        () => SyncRig.create(
          photos: const [],
          texts: const {},
          client: RecordingClient(
            responder: (r) => Completer<http.StreamedResponse>().future,
          ),
        ),
      ))!;
      await tester.pumpWidget(
        _app(
          SyncGate(
            remote: rig.remote,
            keepScreenOn: (on) {
              calls.add(on);
              keepScreenOnByChannel(on); // 테스트에는 채널이 없다 → 조용히 무시
            },
            child: const Text('HOME'),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('홈에서 먼저 볼래요'));
      await tester.tap(find.text('홈에서 먼저 볼래요'));
      await tester.pump();

      expect(calls, [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(minutes: 6)); // 응답 없는 요청의 시간 제한을 흘려보낸다
    });

    testWidgets('첫 분석이 끝나도 자동으로 홈으로 넘어가지 않고 [홈으로]를 눌러야 한다', (tester) async {
      final rig = (await tester.runAsync(
        () => SyncRig.create(photos: const [], texts: const {}),
      ))!;
      await tester.pumpWidget(
        _app(SyncGate(remote: rig.remote, child: const Text('HOME'))),
      );
      await tester.runAsync(() => rig.sync.run());
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('HOME'), findsNothing, reason: '자동 이동 금지');
      expect(find.text('홈으로'), findsOneWidget);

      await tester.tap(find.text('홈으로'));
      await tester.pump();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('진행 중에도 "홈에서 먼저 볼래요"로 나갈 수 있다(동기화는 멈추지 않는다)', (tester) async {
      // 서버 응답이 오지 않아 동기화가 계속 진행 중인 상황.
      final rig = (await tester.runAsync(
        () => SyncRig.create(
          photos: const [],
          texts: const {},
          client: RecordingClient(
            responder: (r) => Completer<http.StreamedResponse>().future,
          ),
        ),
      ))!;
      await tester.pumpWidget(
        _app(SyncGate(remote: rig.remote, child: const Text('HOME'))),
      );
      await tester.pump();
      await tester.pump();

      expect(rig.sync.isRunning, isTrue);
      await tester.ensureVisible(
        find.text('홈에서 먼저 볼래요'),
      ); // 안내 문구만큼 버튼이 아래로 밀린다
      await tester.tap(find.text('홈에서 먼저 볼래요'));
      await tester.pump();
      expect(find.text('HOME'), findsOneWidget);
      expect(rig.sync.isRunning, isTrue);
      // 정리: 응답 없는 요청의 5분 시간 제한(RemineApi.timeout)을 흘려보내 대기 타이머를 비운다.
      await tester.pump(const Duration(minutes: 6));
      expect(rig.sync.isRunning, isFalse);
    });
  });

  group('전체 화면 보기', () {
    Future<void> open(WidgetTester tester, {FakeGalleryReader? reader}) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const PhotoViewerScreen(assetId: 'a1', seed: 1),
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
          reader: reader,
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('기기 사진을 보여 주고 X로 닫는다', (tester) async {
      await open(tester, reader: FakeGalleryReader());

      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-viewer-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsNothing);
    });

    testWidgets('확대하지 않았을 때 아래로 쓸면 닫힌다', (tester) async {
      await open(tester, reader: FakeGalleryReader());

      await tester.fling(
        find.byKey(const ValueKey('photo-viewer')),
        const Offset(0, 400),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsNothing);
    });

    testWidgets('조금만 쓸다 놓으면 닫히지 않고 제자리로 돌아온다', (tester) async {
      await open(tester, reader: FakeGalleryReader());

      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 30));
      await g.moveBy(const Offset(0, 20));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewerScreen), findsOneWidget);
    });

    testWidgets('두 손가락으로 확대하고, 확대한 동안에는 쓸어도 닫히지 않는다', (tester) async {
      await open(tester, reader: FakeGalleryReader());
      final viewer = find.byKey(const ValueKey('photo-viewer'));
      final center = tester.getCenter(viewer);

      final a = await tester.startGesture(center - const Offset(20, 0));
      final b = await tester.startGesture(center + const Offset(20, 0));
      await a.moveBy(const Offset(-60, 0));
      await b.moveBy(const Offset(60, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      final scale = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      expect(scale, greaterThan(1.5), reason: '핀치로 확대되지 않았다');

      await tester.fling(viewer, const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(
        find.byType(PhotoViewerScreen),
        findsOneWidget,
        reason: '확대 중에는 이동만 하고 닫히면 안 된다',
      );
    });

    testWidgets('기기에서 사진이 지워졌으면 "사진이 없어요"와 닫기만 남는다', (tester) async {
      await tester.pumpWidget(
        _app(
          const PhotoViewerScreen(assetId: 'missing', seed: 1),
          reader: FakeGalleryReader(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('사진이 없어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-viewer-close')), findsOneWidget);
    });

    testWidgets('가짜 데이터 모드에서도 열린다(색 블록)', (tester) async {
      await open(tester);
      expect(find.byType(PhotoViewerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
