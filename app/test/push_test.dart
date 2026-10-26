import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/remote/push.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/category_screen.dart';
import 'package:remine/screens/sync_gate.dart';

import 'support/fake_device.dart';
import 'support/fake_push.dart';
import 'support/fake_remote.dart';

const _sheetTitle = '관심사가 생기면 알려 드릴까요?';

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

  group('FCM 토큰', () {
    test('기기 등록에 실제 토큰을 싣는다(임시값 없음)', () async {
      final rig = await SyncRig.create(
        photos: const [],
        push: FakePushClient(),
      );

      await rig.sync.run();

      final register = rig.client.sent.singleWhere(
        (r) => r.method == 'POST' && r.path == '/api/devices',
      );
      expect(register.utf8Text, '{"fcmToken":"fcm-test-token"}');
      expect(register.utf8Text, isNot(contains('pending-fcm-token')));
    });

    test('토큰을 못 받아도 등록·동기화는 된다', () async {
      final rig = await SyncRig.create(
        photos: const [],
        push: FakePushClient(currentToken: null),
      );

      await rig.sync.run();

      expect(await rig.state.deviceId(), 7);
      expect(
        rig.client.sent.singleWhere((r) => r.path == '/api/devices').utf8Text,
        '{"fcmToken":null}',
      );
    });

    test('시작할 때 현재 토큰을 올리고, FCM이 토큰을 바꾸면 다시 올린다', () async {
      final push = FakePushClient();
      final rig = await SyncRig.create(photos: const [], push: push);
      await rig.state.setDeviceId(7);

      await rig.sync.startTokenSync();
      push.refresh.add('fcm-new-token');
      await pumpEventQueue();

      final puts = rig.client.sent
          .where((r) => r.method == 'PUT')
          .map((r) => (r.path, r.utf8Text))
          .toList();
      expect(puts, [
        ('/api/devices/me/fcm-token', '{"fcmToken":"fcm-test-token"}'),
        ('/api/devices/me/fcm-token', '{"fcmToken":"fcm-new-token"}'),
      ]);
    });

    test('아직 등록 전이면 올리지 않는다(등록 요청에 실린다)', () async {
      final rig = await SyncRig.create(
        photos: const [],
        push: FakePushClient(),
      );

      await rig.sync.startTokenSync();

      expect(rig.client.sent, isEmpty);
    });

    test('토큰 올리기가 실패해도 예외가 나지 않는다', () async {
      final rig = await SyncRig.create(
        photos: const [],
        push: FakePushClient(),
        client: RecordingClient(responder: (r) => jsonResponse({}, 404)),
      );
      await rig.state.setDeviceId(7);

      await rig.sync.startTokenSync();
    });
  });

  group('알림 권한은 첫 동기화 뒤 한 번', () {
    Future<void> openGate(
      WidgetTester tester,
      SyncRig rig,
      SettingsStore settings,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SyncGate(
            remote: rig.remote,
            settings: settings,
            child: const Text('HOME'),
          ),
        ),
      );
      await tester.runAsync(() => rig.sync.run());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('시트에서 [알림 받기]를 고르면 권한을 묻고, 다음 실행에는 다시 묻지 않는다', (tester) async {
      final push = FakePushClient();
      final settings = InMemorySettingsStore(true);
      final rig = (await tester.runAsync(
        () => SyncRig.create(photos: const [], push: push),
      ))!;

      await openGate(tester, rig, settings);
      expect(find.text(_sheetTitle), findsOneWidget);
      expect(push.permissionRequests, 0, reason: '시트 전에는 시스템 창을 띄우지 않는다');

      await tester.tap(find.text('알림 받기'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // 시트 닫힘 애니메이션
      expect(push.permissionRequests, 1);
      expect(find.text(_sheetTitle), findsNothing);

      // 앱을 다시 켠 것처럼 새로 띄운다
      await tester.pumpWidget(const SizedBox());
      await openGate(tester, rig, settings);
      expect(find.text(_sheetTitle), findsNothing);
    });

    testWidgets('[나중에]면 권한을 묻지 않는다', (tester) async {
      final push = FakePushClient();
      final rig = (await tester.runAsync(
        () => SyncRig.create(photos: const [], push: push),
      ))!;

      await openGate(tester, rig, InMemorySettingsStore(true));
      await tester.tap(find.text('나중에'));
      await tester.pump(const Duration(seconds: 1));

      expect(push.permissionRequests, 0);
    });

    testWidgets('첫 동기화가 끝나지 않았으면 묻지 않는다', (tester) async {
      final rig = (await tester.runAsync(
        () => SyncRig.create(
          photos: const [],
          push: FakePushClient(),
          client: RecordingClient()..throwOnSend = Exception('offline'),
        ),
      ))!;

      await openGate(tester, rig, InMemorySettingsStore(true));

      expect(find.text(_sheetTitle), findsNothing);
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

    void expectCategory(WidgetTester tester, Category category, String tag) {
      final screen = tester.widget<CategoryScreen>(find.byType(CategoryScreen));
      expect(screen.category, category);
      expect(screen.initialTag, tag);
    }

    testWidgets('꺼진 앱을 알림으로 켜면 그 태그로 거른 카테고리 화면이 열린다', (tester) async {
      await openApp(
        tester,
        initial: const PushTarget(tag: '신발', category: Category.shopping),
      );

      expectCategory(tester, Category.shopping, '신발');
    });

    testWidgets('백그라운드에서 알림을 누르면 그 화면이 열린다', (tester) async {
      final push = await openApp(tester);
      expect(find.byType(CategoryScreen), findsNothing);

      push.tapEvents.add(
        const PushTarget(tag: '전시', category: Category.entertainment),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expectCategory(tester, Category.entertainment, '전시');
    });
  });
}
