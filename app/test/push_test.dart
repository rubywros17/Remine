import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remote/push.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/tag_screen.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/screens/notification_screen.dart';
import 'package:remine/screens/settings_screen.dart';
import 'package:remine/screens/sync_gate.dart';

import 'support/fake_device.dart';
import 'support/fake_push.dart';
import 'support/fake_remote.dart';

const _askSettings = '휴대폰 설정에서 알림을 켜 주세요';

void main() {
  group('PushTarget.fromData', () {
    test('관심사 알림이면 태그·카테고리를 읽는다', () {
      expect(
        PushTarget.fromData({
          'type': 'interest',
          'tag': '신발',
          'category': 'SHOPPING',
        }),
        const PushTarget(tag: '신발', category: Category.shopping),
      );
    });

    test('모르는 알림·이상한 값이면 null', () {
      for (final data in <Map<String, dynamic>>[
        {},
        {'type': 'other', 'tag': '신발', 'category': 'SHOPPING'},
        {'type': 'interest', 'tag': '', 'category': 'SHOPPING'},
        {'type': 'interest', 'tag': '신발', 'category': 'NOPE'},
        {'type': 'interest', 'category': 'SHOPPING'},
      ]) {
        expect(PushTarget.fromData(data), isNull, reason: '$data');
      }
    });
  });

  group('FCM 토큰은 알림을 켰을 때만 서버에', () {
    Future<SyncRig> rigWith(
      bool? enabled, {
      FakePushClient? push,
      RecordingClient? client,
    }) async {
      final rig = await SyncRig.create(
        photos: const [],
        push: push ?? FakePushClient(),
        client: client,
      );
      if (enabled != null) await rig.settings.setNotificationsEnabled(enabled);
      return rig;
    }

    List<(String, String)> tokenCalls(SyncRig rig) => [
      for (final r in rig.client.sent)
        if (r.path == '/api/devices/me/fcm-token') (r.method, r.utf8Text),
    ];

    test('켜져 있으면 기기 등록에 실제 토큰을 싣는다(임시값 없음)', () async {
      final rig = await rigWith(true);

      await rig.sync.run();

      final body = rig.client.sent
          .singleWhere((r) => r.method == 'POST' && r.path == '/api/devices')
          .utf8Text;
      expect(body, '{"fcmToken":"fcm-test-token"}');
      expect(body, isNot(contains('pending-fcm-token')));
    });

    test('아직 안 골랐거나 껐으면 토큰 없이 등록한다', () async {
      for (final enabled in [null, false]) {
        final rig = await rigWith(enabled);

        await rig.sync.run();

        expect(await rig.state.deviceId(), 7);
        expect(
          rig.client.sent.singleWhere((r) => r.path == '/api/devices').utf8Text,
          '{"fcmToken":null}',
          reason: '$enabled',
        );
      }
    });

    test('켜져 있으면 시작할 때 토큰을 올리고, FCM이 바꾸면 다시 올린다', () async {
      final push = FakePushClient();
      final rig = await rigWith(true, push: push);
      await rig.state.setDeviceId(7);

      await rig.sync.startTokenSync();
      push.refresh.add('fcm-new-token');
      await pumpEventQueue();

      expect(tokenCalls(rig), [
        ('PUT', '{"fcmToken":"fcm-test-token"}'),
        ('PUT', '{"fcmToken":"fcm-new-token"}'),
      ]);
    });

    test('꺼져 있으면 시작할 때 서버 토큰을 지우고, 토큰이 바뀌어도 올리지 않는다', () async {
      final push = FakePushClient();
      final rig = await rigWith(false, push: push);
      await rig.state.setDeviceId(7);

      await rig.sync.startTokenSync();
      push.refresh.add('fcm-new-token');
      await pumpEventQueue();

      expect(tokenCalls(rig), [('DELETE', '')]);
    });

    test('아직 안 골랐으면 아무것도 하지 않는다', () async {
      final rig = await rigWith(null);
      await rig.state.setDeviceId(7);

      await rig.sync.startTokenSync();

      expect(rig.client.sent, isEmpty);
    });

    test('켜고 끄면 저장하고 서버 토큰을 올리거나 지운다', () async {
      final rig = await rigWith(null);
      await rig.state.setDeviceId(7);

      await rig.sync.setNotifications(true);
      expect(await rig.settings.notificationsEnabled(), isTrue);
      await rig.sync.setNotifications(false);
      expect(await rig.settings.notificationsEnabled(), isFalse);

      expect(tokenCalls(rig).map((c) => c.$1), ['PUT', 'DELETE']);
    });

    test('서버 호출이 실패해도 예외가 나지 않고 설정은 저장된다', () async {
      final rig = await rigWith(
        null,
        client: RecordingClient(responder: (r) => jsonResponse({}, 404)),
      );
      await rig.state.setDeviceId(7);

      await rig.sync.setNotifications(false);
      await rig.sync.startTokenSync();

      expect(await rig.settings.notificationsEnabled(), isFalse);
    });
  });

  group('알림 안내는 첫 실행 때 첫 분석 전에 한 번', () {
    // 실제 앱과 같은 순서: 알림 안내 → 첫 분석(SyncGate)
    Widget gate(SyncRig rig) => MaterialApp(
      home: NotificationGate(
        remote: rig.remote,
        settings: rig.settings,
        child: SyncGate(remote: rig.remote, child: const Text('HOME')),
      ),
    );

    Future<void> open(WidgetTester tester, SyncRig rig) async {
      await tester.pumpWidget(gate(rig));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    Future<SyncRig> newRig(WidgetTester tester, FakePushClient push) async =>
        (await tester.runAsync(
          () => SyncRig.create(photos: const [], push: push),
        ))!;

    String registerBody(SyncRig rig) => rig.client.sent
        .singleWhere((r) => r.method == 'POST' && r.path == '/api/devices')
        .utf8Text;

    testWidgets('첫 분석 전에 묻고, 시스템 창은 [알림 받기] 뒤에만 뜬다', (tester) async {
      final push = FakePushClient();
      final rig = await newRig(tester, push);

      await open(tester, rig);

      expect(find.text(notificationTitle), findsOneWidget);
      expect(push.permissionRequests, 0, reason: '안내 화면 전에는 시스템 창을 띄우지 않는다');
      expect(rig.client.sent, isEmpty, reason: '고르기 전에는 첫 분석(기기 등록)을 시작하지 않는다');
    });

    testWidgets('[알림 받기] → 허용이면 켜고, 첫 기기 등록에 토큰을 싣는다', (tester) async {
      final push = FakePushClient();
      final rig = await newRig(tester, push);

      await open(tester, rig);
      await choose(tester, '알림 받기');
      await tester.runAsync(() => rig.sync.run());

      expect(push.permissionRequests, 1);
      expect(await rig.settings.notificationsEnabled(), isTrue);
      expect(registerBody(rig), '{"fcmToken":"fcm-test-token"}');
    });

    testWidgets('권한 창에서 거부하면 꺼짐으로 저장하고 첫 분석은 그대로 진행한다', (tester) async {
      final rig = await newRig(tester, FakePushClient()..grant = false);

      await open(tester, rig);
      await choose(tester, '알림 받기');
      await tester.runAsync(() => rig.sync.run());

      expect(await rig.settings.notificationsEnabled(), isFalse);
      expect(find.text(notificationTitle), findsNothing);
      expect(registerBody(rig), '{"fcmToken":null}');
    });

    testWidgets('[나중에]면 권한을 묻지 않고 꺼짐, 다음 실행에는 다시 묻지 않는다', (tester) async {
      final push = FakePushClient();
      final rig = await newRig(tester, push);

      await open(tester, rig);
      await choose(tester, '나중에');

      expect(push.permissionRequests, 0);
      expect(find.text(notificationTitle), findsNothing);
      expect(await rig.settings.notificationsEnabled(), isFalse);

      await tester.pumpWidget(const SizedBox());
      await open(tester, rig);
      expect(find.text(notificationTitle), findsNothing);
    });

    testWidgets('뒤로 가기는 [나중에]와 같다', (tester) async {
      final push = FakePushClient();
      final rig = await newRig(tester, push);

      await open(tester, rig);
      await tester.binding.handlePopRoute();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(push.permissionRequests, 0);
      expect(await rig.settings.notificationsEnabled(), isFalse);
      expect(find.text(notificationTitle), findsNothing);
    });

    testWidgets('첫 분석 완료 화면의 [홈으로] 뒤에는 묻지 않는다', (tester) async {
      final rig = await newRig(tester, FakePushClient());
      await tester.pumpWidget(
        MaterialApp(home: SyncGate(remote: rig.remote, child: const Text('HOME'))),
      );
      await tester.runAsync(() => rig.sync.run());
      await tester.pump(const Duration(seconds: 3));
      await tester.ensureVisible(find.text('홈으로'));
      await tester.tap(find.text('홈으로'));
      await tester.pump();

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text(notificationTitle), findsNothing);
    });
  });

  group('설정의 알림 받기 스위치', () {
    // 설정의 스위치 두 개 중 아래(이미지 분석 다음)가 알림 받기다.
    final notifySwitch = find.byType(Switch).last;

    Future<SyncRig> openSettings(
      WidgetTester tester,
      FakePushClient push, {
      bool? enabled,
    }) async {
      final rig = (await tester.runAsync(() async {
        final rig = await SyncRig.create(photos: const [], push: push);
        await rig.state.setDeviceId(7);
        if (enabled != null) {
          await rig.settings.setNotificationsEnabled(enabled);
        }
        return rig;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      settings: rig.settings,
                      remote: rig.remote,
                    ),
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      return rig;
    }

    bool isOn(WidgetTester tester) => tester.widget<Switch>(notifySwitch).value;

    Future<void> toggle(WidgetTester tester) async {
      await tester.tap(notifySwitch);
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 스낵바가 올라오는 시간
    }

    testWidgets('켜 두었어도 휴대폰 권한이 없으면 꺼짐으로 보인다', (tester) async {
      await openSettings(
        tester,
        FakePushClient()..granted = false,
        enabled: true,
      );

      expect(isOn(tester), isFalse);
    });

    testWidgets('켜면 권한을 요청하고 토큰을 올린다, 끄면 서버 토큰을 지운다', (tester) async {
      final push = FakePushClient();
      final rig = await openSettings(tester, push, enabled: false);

      await toggle(tester);
      expect(push.permissionRequests, 1);
      expect(isOn(tester), isTrue);

      await toggle(tester);
      expect(isOn(tester), isFalse);
      expect(await rig.settings.notificationsEnabled(), isFalse);
      expect(
        rig.client.sent
            .where((r) => r.path == '/api/devices/me/fcm-token')
            .map((r) => r.method),
        ['PUT', 'DELETE'],
      );
    });

    testWidgets('거부돼 있으면 꺼진 채로 휴대폰 설정 안내 → [설정 열기], 3초 뒤 사라진다', (tester) async {
      final push = FakePushClient()..grant = false;
      final rig = await openSettings(tester, push, enabled: false);

      await toggle(tester);

      expect(isOn(tester), isFalse);
      expect(rig.client.sent, isEmpty);
      expect(find.text(_askSettings), findsOneWidget);
      await tester.tap(find.text('설정 열기'));
      expect(push.settingsOpened, 1);

      await toggle(tester);
      await tester.pumpAndSettle(); // 앞 스낵바가 닫히고 새 스낵바가 다 올라온 뒤부터 3초를 센다
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text(_askSettings), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(_askSettings), findsNothing);
    });

    testWidgets('설정 화면을 나가면 스낵바도 닫힌다(홈까지 따라가지 않는다)', (tester) async {
      await openSettings(
        tester,
        FakePushClient()..grant = false,
        enabled: false,
      );

      await toggle(tester);
      expect(find.text(_askSettings), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text(_askSettings), findsNothing);
    });
  });

  group('디버그 테스트 알림', () {
    testWidgets('[테스트 알림 보내기] → 바로 요청하고 5초 대기는 서버가, 결과를 로그에 남긴다', (
      tester,
    ) async {
      final logs = <String>[];
      final rig = (await tester.runAsync(() async {
        final rig = await SyncRig.create(
          photos: const [],
          push: FakePushClient(),
          log: logs.add,
        );
        await rig.state.setDeviceId(7);
        return rig;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: DebugOcrScreen(
            services: fakeServices(
              FakeGalleryReader(photos: const []),
              remote: rig.remote,
            ),
          ),
        ),
      );
      await tester.pump();
      Iterable<SentRequest> calls() => rig.client.sent.where(
        (r) => r.method == 'POST' && r.path == '/api/dev/push-test',
      );

      await tester.tap(find.text('테스트 알림 보내기'));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(calls(), hasLength(1), reason: '앱이 기다리지 않는다(내려가도 요청은 이미 나감)');
      expect(calls().single.query, {'delaySeconds': '5'});
      expect(logs, contains('[api] POST /api/dev/push-test result=SENT'));
      expect(find.text('테스트 알림 보냈어.'), findsWidgets);
    });
  });

  group('알림 탭 → 관심사 화면', () {
    Future<FakePushClient> openApp(
      WidgetTester tester, {
      PushTarget? initial,
    }) async {
      final push = FakePushClient(initial: initial);
      final rig = (await tester.runAsync(
        () => SyncRig.create(photos: const [], push: push),
      ))!;
      await tester.pumpWidget(
        RemineApp(
          repository: FakeScreenshotRepository(),
          device: fakeServices(
            FakeGalleryReader(photos: const []),
            remote: rig.remote,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return push;
    }

    void expectTag(WidgetTester tester, String tag) {
      expect(tester.widget<TagScreen>(find.byType(TagScreen)).tag, tag);
    }

    testWidgets('꺼진 앱을 알림으로 켜면 그 태그 모아보기 화면이 열린다', (tester) async {
      await openApp(
        tester,
        initial: const PushTarget(tag: '신발', category: Category.shopping),
      );

      expectTag(tester, '신발');
    });

    testWidgets('백그라운드에서 알림을 누르면 그 화면이 열린다', (tester) async {
      final push = await openApp(tester);
      expect(find.byType(TagScreen), findsNothing);

      push.tapEvents.add(
        const PushTarget(tag: '전시', category: Category.entertainment),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expectTag(tester, '전시');
    });
  });
}
