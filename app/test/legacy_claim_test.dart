// [임시] 토큰 도입 전에 등록한 기기의 이전(legacy-claim). 서버의 LegacyDeviceClaim과 함께 지운다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_status.dart';

import 'support/fake_push.dart';
import 'support/fake_remote.dart';

/// 예전 앱이 남긴 상태: 숫자 기기 id 5, p0은 이미 서버에 보냄(p1은 아직).
Future<SyncRig> _oldApp(
  http.StreamedResponse Function(SentRequest r) claim, {
  bool notifications = true,
}) async {
  late final RecordingClient client;
  client = RecordingClient(
    responder: (r) =>
        r.path == '/api/devices/legacy-claim' ? claim(r) : client.defaultFor(r),
  );
  final rig = await SyncRig.create(
    photos: photosNamed({'p0': 'Screenshot_1.png', 'p1': 'Screenshot_2.png'}),
    texts: {'p0': '첫 번째 캡처 글자', 'p1': '두 번째 캡처 글자'},
    push: FakePushClient(),
    client: client,
  );
  await rig.settings.setNotificationsEnabled(notifications);
  rig.state.legacyId = 5;
  await rig.state.putEntry(
    const SyncEntry(
      assetId: 'p0',
      modifiedAt: 1000,
      status: SyncStatusCode.synced,
    ),
  );
  return rig;
}

Iterable<SentRequest> _to(SyncRig rig, String path) =>
    rig.client.sent.where((r) => r.path == path);

void main() {
  test('예전 id와 FCM 토큰으로 한 번 이전하면 그 토큰을 쓰고 기존 전송 기록을 이어 간다', () async {
    final rig = await _oldApp((_) => jsonResponse({'token': 'tok-5'}));

    await rig.sync.run();

    expect(
      _to(rig, '/api/devices/legacy-claim').single.utf8Text,
      '{"deviceId":5,"fcmToken":"fcm-test-token"}',
    );
    expect(_to(rig, '/api/devices'), isEmpty); // 새로 등록하지 않았다
    expect(await rig.state.deviceToken(), 'tok-5');
    expect(await rig.state.legacyDeviceId(), isNull); // 숫자 id는 지웠다
    // p0은 이미 보낸 것으로 남아 있어 다시 보내지 않고, p1만 새 토큰으로 갔다
    final analyze = _to(rig, '/api/screenshots/analyze').toList();
    expect(analyze.map((r) => r.deviceToken).toSet(), {'tok-5'});
    expect(analyze.map((r) => r.utf8Text).join(), isNot(contains('"p0"')));
    expect(analyze.map((r) => r.utf8Text).join(), contains('"p1"'));
    // 숫자 id는 이전 요청 말고는 어디에도 싣지 않는다
    for (final r in rig.client.sent.where(
      (r) => r.path != '/api/devices/legacy-claim',
    )) {
      expect(r.headers.containsKey('X-Device-Id'), isFalse);
    }
  });

  for (final (name, status) in [('거절(403)', 403), ('창구 닫힘(404)', 404)]) {
    test('이전이 $name이면 새로 등록하고 전체를 다시 보낸다', () async {
      final rig = await _oldApp(
        (_) => jsonResponse({'code': 'LEGACY_CLAIM_REJECTED'}, status),
      );

      await rig.sync.run();

      expect(_to(rig, '/api/devices/legacy-claim'), hasLength(1));
      expect(_to(rig, '/api/devices'), hasLength(1));
      expect(await rig.state.deviceToken(), 'tok-7');
      expect(await rig.state.legacyDeviceId(), isNull);
      // 새 기기는 서버에 아무것도 없으니 p0도 다시 보냈다
      final sent = _to(rig, '/api/screenshots/analyze').map((r) => r.utf8Text);
      expect(sent.join(), allOf(contains('"p0"'), contains('"p1"')));
      expect((await rig.state.entry('p0'))?.status, SyncStatusCode.synced);
    });
  }

  test('알림이 꺼져 FCM 토큰이 없으면 이전 요청에 싣지 않는다(서버가 거절 → 새로 등록)', () async {
    final rig = await _oldApp(
      (r) => jsonResponse({'code': 'LEGACY_CLAIM_REJECTED'}, 403),
      notifications: false,
    );

    await rig.sync.run();

    expect(
      _to(rig, '/api/devices/legacy-claim').single.utf8Text,
      '{"deviceId":5,"fcmToken":null}',
    );
    expect(await rig.state.deviceToken(), 'tok-7');
  });

  test('이전 중 서버에 닿지 못하면 새로 등록하지 않고 다음에 다시 시도한다', () async {
    final rig = await _oldApp((_) => throw const SocketException('refused'));

    await rig.sync.run();

    expect(_to(rig, '/api/devices'), isEmpty);
    expect(await rig.state.deviceToken(), isNull);
    expect(await rig.state.legacyDeviceId(), 5); // 숫자 id를 지우지 않았다
    expect((await rig.state.entry('p0'))?.status, SyncStatusCode.synced);
    expect(rig.status.issue, SyncIssue.offline);
  });
}
