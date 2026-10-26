import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remine/data/remote/api_client.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';

import 'support/fake_push.dart';
import 'support/fake_remote.dart';

/// 서버 재시작(H2 초기화) 재현: 서버가 아는 기기만 받고, 모르는 기기 id는 전부 404 DEVICE_NOT_FOUND.
class RestartableServer {
  RestartableServer() {
    client = RecordingClient(responder: _respond);
  }

  late final RecordingClient client;
  final Set<int> known = {};
  int _nextId = 7;

  /// 서버를 다시 켠 것처럼 모든 기기를 잊는다.
  void restart() => known.clear();

  int get registrations =>
      client.sent.where((r) => r.path == '/api/devices').length;

  FutureOr<http.StreamedResponse> _respond(SentRequest r) {
    if (r.method == 'POST' && r.path == '/api/devices') {
      final id = _nextId++;
      known.add(id);
      return jsonResponse({'deviceId': id});
    }
    final id = r.deviceId;
    if (id != null && !known.contains(id)) {
      return jsonResponse({'code': 'DEVICE_NOT_FOUND'}, 404);
    }
    if (r.method == 'GET' &&
        {
          '/api/interests',
          '/api/categories/summary',
          '/api/screenshots',
        }.contains(r.path)) {
      return jsonResponse({}); // 해석은 저장소가 알아서(빈 결과)
    }
    return client.defaultFor(r);
  }
}

/// analyze 요청에 실린 asset id들.
Iterable<String> assetIdsIn(SentRequest r) =>
    RegExp(r'"localAssetId":"([^"]+)"')
        .allMatches(r.text)
        .map((m) => m.group(1)!);

void main() {
  test(
    '서버 재시작 뒤 모든 기기 요청이 404여도 재등록은 한 번, 원래 요청은 새 id로 성공하고 전체를 다시 보낸다',
    () async {
      final server = RestartableServer();
      final rig = await SyncRig.create(
        photos: photosNamed({
          'p0': 'Screenshot_1.png',
          'p1': 'Screenshot_2.png',
        }),
        texts: {'p0': '첫 번째 캡처 글자', 'p1': '두 번째 캡처 글자'},
        push: FakePushClient(),
        client: server.client,
      );
      await rig.settings.setNotificationsEnabled(true);
      await rig.sync.run();
      expect(await rig.state.deviceId(), 7);
      expect((await rig.state.entry('p0'))?.status, SyncStatusCode.synced);

      server.restart();
      final before = rig.client.sent.length;

      // 홈이 여러 화면 데이터를 한꺼번에 부르고, 토큰도 올리는 상황
      await Future.wait([
        rig.repository.summary(),
        rig.repository.interests(),
        rig.repository.list(),
        rig.sync.startTokenSync(),
      ]);
      // 재등록이 예약한 전체 재전송이 끝날 때까지
      await pumpEventQueue();
      await rig.sync.run();

      final after = rig.client.sent.skip(before).toList();
      expect(server.registrations, 2, reason: '재시작 뒤 재등록은 한 번');
      expect(await rig.state.deviceId(), 8);
      expect(rig.status.issue, SyncIssue.none);
      // 원래 요청들은 404 한 번 뒤 새 id(8)로 한 번씩 다시 갔다
      for (final path in [
        '/api/categories/summary',
        '/api/interests',
        '/api/screenshots',
        '/api/devices/me/fcm-token',
      ]) {
        expect(after.where((r) => r.path == path).map((r) => r.deviceId), [
          7,
          8,
        ], reason: path);
      }
      // 재등록에 토큰이 실리고(알림 켬), 서버가 잊은 캡처를 새 id로 전부 다시 보냈다
      expect(
        after.singleWhere((r) => r.path == '/api/devices').utf8Text,
        '{"fcmToken":"fcm-test-token"}',
      );
      final resent = after.where((r) => r.path == '/api/screenshots/analyze');
      expect(resent.map((r) => r.deviceId).toSet(), {8});
      expect(resent.expand(assetIdsIn).toSet(), {'p0', 'p1'});
    },
  );

  test('동기화 중 analyze가 404여도 재등록 한 번 → 같은 배치 재시도 → 전체 재전송', () async {
    final server = RestartableServer();
    final rig = await SyncRig.create(
      photos: photosNamed({'p0': 'Screenshot_1.png'}),
      texts: {'p0': '캡처 글자'},
      client: server.client,
    );
    await rig.state.setDeviceId(99); // 서버가 모르는 옛 id

    await rig.sync.run();

    expect(server.registrations, 1);
    expect(await rig.state.deviceId(), 7);
    expect((await rig.state.entry('p0'))?.status, SyncStatusCode.synced);
    expect(rig.status.issue, SyncIssue.none);
  });

  test('기기 없음이 아닌 404(없는 캡처·없는 경로)는 재등록하지 않고 rejected로 둔다', () async {
    final server = RestartableServer();
    final rig = await SyncRig.create(photos: const [], client: server.client);
    await rig.sync.run(); // 기기 7 등록

    await expectLater(
      rig.repository.updateCategory(
        12345,
        Category.place,
      ), // 없는 캡처 → code 없는 404
      throwsA(
        isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.rejected)
            .having((e) => e.deviceGone, 'deviceGone', isFalse),
      ),
    );
    expect(server.registrations, 1);
  });

  test('4xx는 "서버가 불안정해요"가 아니라 rejected, 앱 내부 예외는 internal', () async {
    final rejected = await SyncRig.create(
      photos: const [],
      client: RecordingClient(responder: (r) => jsonResponse({}, 400)),
    );
    await rejected.sync.run();
    expect(rejected.status.issue, SyncIssue.rejected);
    expect(rejected.status.bannerMessage, isNot('서버가 불안정해요'));

    final internal = await SyncRig.create(
      photos: const [],
      client: RecordingClient()..throwOnSend = StateError('boom'),
    );
    await internal.sync.run();
    expect(internal.status.issue, SyncIssue.internal);
  });

  test('같은 GET이 진행 중이면 합친다(요청 하나)', () async {
    final gate = Completer<void>();
    final client = RecordingClient(
      responder: (r) async {
        await gate.future;
        return jsonResponse({'items': []});
      },
    );
    final api = RemineApi('http://localhost:8080', client);

    final calls = [
      api.interestsJson(7),
      api.interestsJson(7),
      api.interestsJson(7),
      api.summaryJson(7), // 다른 경로는 따로
    ];
    gate.complete();
    await Future.wait(calls);

    expect(client.sent.where((r) => r.path == '/api/interests'), hasLength(1));
    expect(client.sent, hasLength(2));

    await api.interestsJson(7); // 끝난 뒤에는 다시 보낸다
    expect(client.sent.where((r) => r.path == '/api/interests'), hasLength(2));
  });
}
