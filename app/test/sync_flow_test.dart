import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

const _long =
    '서울 성수동 팝업스토어 오픈 안내 운영 시간 열한 시부터 여덟 시까지 주말에는 줄이 길어서 평일 방문을 추천해요 '
    '주소는 성수이로 이십 길 입장은 무료이고 사전 예약은 필요하지 않아요 주차는 근처 공영주차장을 이용해 주세요 '
    '굿즈는 현장 구매만 가능합니다 영업시간과 메뉴 가격은 매장 사정에 따라 바뀔 수 있으니 방문 전에 확인해 주세요 '
    '근처 카페와 식당도 함께 둘러보기 좋아요';

Future<SyncRig> rigOf(
  int n, {
  RecordingClient? client,
  int photoLimit = 0,
  String text = _long,
}) => SyncRig.create(
  photos: fakePhotos(n),
  texts: {for (var i = 0; i < n; i++) 'p$i': text},
  client: client,
  photoLimit: photoLimit,
);

List<int> idsIn(SentRequest r) =>
    RegExp(r'"localAssetId":"p(\d+)"')
        .allMatches(r.utf8Text)
        .map((m) => int.parse(m.group(1)!))
        .toList();

void main() {
  test('45장은 서버 설정(20장)대로 20·20·5장으로 나눠 보내고 배치마다 홈을 갱신한다', () async {
    final rig = await rigOf(45);
    await rig.sync.run();

    final calls = rig.client.analyzeCalls.toList();
    expect(calls.map((c) => idsIn(c).length), [20, 20, 5]);
    // 배치가 끝날 때마다 진행이 20, 40, 45로 올라간 상태에서 홈에 알린다(+ 마지막 마무리 알림).
    expect(rig.batches.take(3), [20, 40, 45]);
    expect(rig.status.done, 45);
    expect(rig.status.counts[Category.info], 45);
    expect(rig.status.issue, SyncIssue.none);
  });

  test('기준값·장수 상한은 /api/config에서 받는다', () async {
    final client = RecordingClient(
      responder: (r) {
        if (r.path == '/api/config') {
          return jsonResponse({
            'imageThresholdChars': 150,
            'maxBatchSize': 5,
            'imageMaxBytes': 1048576,
            'imageMaxLongSide': 1024,
            'imageContentType': 'image/jpeg',
            'maxRequestBytes': 12582912,
          });
        }
        return RecordingClient().defaultFor(r);
      },
    );
    final rig = await rigOf(12, client: client);
    await rig.sync.run();

    expect(rig.client.analyzeCalls.map((c) => idsIn(c).length), [5, 5, 2]);
  });

  test('두 번째 실행은 바뀌지 않은 캡처를 다시 보내지 않는다(증분)', () async {
    final rig = await rigOf(3);
    await rig.sync.run();
    final first = rig.client.analyzeCalls.length;
    await rig.sync.run();
    expect(rig.client.analyzeCalls.length, first);
  });

  test('사진이 바뀌면(modifiedAt) 그 장만 다시 보낸다', () async {
    final rig = await rigOf(3);
    await rig.sync.run();
    final old = rig.reader.photos[1];
    rig.reader.photos[1] = GalleryPhoto(
      id: old.id,
      fileName: old.fileName,
      takenAt: old.takenAt,
      modifiedAt: old.modifiedAt + 1, // 사진이 바뀐 것처럼
    );
    await rig.sync.run();

    final last = rig.client.analyzeCalls.last;
    expect(idsIn(last), [1]);
  });

  test('failed(LLM 실패)는 다음 실행 때 다시 보낸다', () async {
    final rig = await rigOf(3);
    rig.client.failWith['p1'] = 'LLM_CALL_FAILED';
    await rig.sync.run();
    expect(rig.status.issue, SyncIssue.partial);
    expect(rig.status.failedCount, 1);
    expect(rig.status.issueMessage, contains('1장'));

    rig.client.failWith.clear();
    await rig.sync.run();
    expect(idsIn(rig.client.analyzeCalls.last), [1]);
    expect(rig.status.issue, SyncIssue.none);
  });

  test('IMAGE_TOO_LARGE는 더 줄여서, IMAGE_INVALID는 이미지 없이 다시 보낸다', () async {
    var round = 0;
    final client = RecordingClient(
      responder: (r) {
        if (r.path == '/api/screenshots/analyze') {
          round++;
          if (round == 1) {
            return jsonResponse({
              'analyzed': <Object>[],
              'skipped': <Object>[],
              'failed': [
                {'localAssetId': 'p0', 'reason': 'IMAGE_TOO_LARGE'},
                {'localAssetId': 'p1', 'reason': 'IMAGE_INVALID'},
              ],
            });
          }
        }
        return RecordingClient().defaultFor(r);
      },
    );
    final rig2 = await SyncRig.create(
      photos: fakePhotos(2),
      texts: {'p0': '짧음', 'p1': '짧음'},
      client: client,
    );
    await rig2.sync.run();

    final calls = client.analyzeCalls.toList();
    expect(calls, hasLength(2));
    expect(calls[1].text, contains('name="image.p0"'));
    expect(calls[1].text, isNot(contains('name="image.p1"')));
    // p0은 더 낮은 단계(품질·크기)로 다시 만들었다.
    expect(rig2.shrinker.calls.length, 3);
    expect(rig2.shrinker.calls.last.$2, lessThan(rig2.shrinker.calls.first.$2));
  });

  test('동기화는 한 번에 하나만 돈다(겹쳐 부르면 진행 중인 실행을 기다린다)', () async {
    final rig = await rigOf(3);
    await Future.wait([rig.sync.run(), rig.sync.run(), rig.sync.run()]);

    expect(rig.client.sent.where((r) => r.path == '/api/config'), hasLength(1));
    expect(rig.client.analyzeCalls, hasLength(1));
    expect(rig.sync.isRunning, isFalse);
  });

  test('서버가 기기를 모르면(404) 다시 등록하고 처음부터 다시 보낸다', () async {
    var analyzeCalls = 0;
    late final RecordingClient client;
    client = RecordingClient(
      responder: (r) {
        if (r.path == '/api/screenshots/analyze' && ++analyzeCalls == 1) {
          return jsonResponse({'error': 'unknown device'}, 404);
        }
        return client.defaultFor(r);
      },
    );
    final rig = await rigOf(2, client: client);
    await rig.sync.run();

    expect(client.sent.where((r) => r.path == '/api/devices'), hasLength(2));
    expect(rig.status.issue, SyncIssue.none);
    expect((await rig.state.entry('p0'))?.status, SyncStatusCode.synced);
  });

  test('디버그 장수 제한(SYNC_LIMIT)만큼만 보낸다', () async {
    final rig = await rigOf(30, photoLimit: 12);
    await rig.sync.run();

    expect(rig.client.analyzeCalls.map((c) => idsIn(c).length), [12]);
  });

  test('기기 등록은 한 번만 하고 기기 id를 저장해 둔다', () async {
    final rig = await rigOf(2);
    await rig.sync.run();
    await rig.sync.run();

    expect(
      rig.client.sent.where((r) => r.path == '/api/devices'),
      hasLength(1),
    );
    expect(await rig.state.deviceId(), 7);
  });

  group('남은 시간 표시', () {
    test('몇 장 처리하기 전에는 예상하지 않고, 이후에는 속도로 계산한다', () {
      var now = DateTime(2026, 10, 21, 12);
      final status = SyncStatus(now: () => now);
      status.begin(100);
      expect(status.eta, isNull);
      now = now.add(const Duration(minutes: 1));
      status.advance(20); // 20장에 1분 → 80장 남음 = 4분
      expect(status.eta, const Duration(minutes: 4));
    });

    test('문구', () {
      expect(formatEta(const Duration(seconds: 20)), '1분 미만 남았어요');
      expect(formatEta(const Duration(minutes: 4)), '약 4분 남았어요');
      expect(formatEta(const Duration(minutes: 61)), '약 1시간 1분 남았어요');
      expect(formatEta(const Duration(minutes: 120)), '약 2시간 남았어요');
    });
  });
}
