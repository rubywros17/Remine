import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/remote/remote_state_store.dart';

import 'support/fake_remote.dart';

/// 기기에서 끝난 캡처(메신저·민감·글자 없음)는 로컬 기록만 남겨 다음 실행에서 다시 처리하지 않는다.
/// 그 기록의 asset id는 서버로 보내지 않는다.
void main() {
  const card = '4111 1111 1111 1111';

  // 이미지 동의를 끈다: 켜져 있으면 글자 없는 캡처는 이미지와 함께 서버로 가는 게 맞는 동작이다.
  Future<SyncRig> rig(List<GalleryPhoto> photos) => SyncRig.create(
    photos: photos,
    consent: false,
    texts: {
      'msg': '오늘 몇 시에 만나 ' * 10,
      'secret': '카드번호 $card 유효기간',
      'blank': '',
      'normal': '봄 니트 가디건 신상 할인 ' * 10,
    },
  );

  List<GalleryPhoto> photos({int blankModified = 1003}) => [
    for (final p in photosNamed({
      'msg': 'Screenshot_20261101_101010_KakaoTalk.jpg',
      'secret': 'Screenshot_20261101_101011_Chrome.jpg',
      'blank': 'Screenshot_20261101_101012_Chrome.jpg',
      'normal': 'Screenshot_20261101_101013_Chrome.jpg',
    }))
      p.id == 'blank'
          ? GalleryPhoto(
              id: p.id,
              fileName: p.fileName,
              takenAt: p.takenAt,
              modifiedAt: blankModified,
            )
          : p,
  ];

  const deviceIds = ['msg', 'secret', 'blank'];

  void expectNeverSent(SyncRig r) {
    final body = r.client.sent.map((s) => s.utf8Text).join('\n');
    for (final id in deviceIds) {
      expect(body, isNot(contains('"$id"')), reason: '$id가 요청에 실렸다');
    }
  }

  test('첫 실행에서 기기 판정한 캡처는 기록만 남기고, 다음 실행 대상에서 빠진다', () async {
    final r = await rig(photos());
    await r.sync.run();
    expect(r.status.total, 4);
    for (final id in deviceIds) {
      expect(
        (await r.state.entry(id))?.status,
        SyncStatusCode.deviceOnly,
        reason: id,
      );
    }
    expect((await r.state.entry('normal'))?.status, SyncStatusCode.synced);

    final before = r.client.analyzeCalls.length;
    await r.sync.run();
    expect(r.status.total, 0, reason: '다시 처리할 것이 없다');
    expect(r.client.analyzeCalls.length, before);
    expectNeverSent(r);
  });

  test('바뀐 캡처는 다시 판정한다(기기 판정도 마찬가지)', () async {
    final r = await rig(photos());
    await r.sync.run();

    final changed = await rig(photos(blankModified: 2000));
    // 같은 기록을 이어받은 것처럼 첫 실행의 기록을 옮긴다.
    for (final p in photos()) {
      final e = await r.state.entry(p.id);
      if (e != null) await changed.state.putEntry(e);
    }
    await changed.state.setDeviceId(7);
    await changed.sync.run();
    expect(changed.status.total, 1, reason: 'blank만 바뀌었다');
    expectNeverSent(changed);
  });

  test('기기 판정 기록이 있는 캡처가 나중에 자기 캡처로 판정돼도 forget에 싣지 않는다', () async {
    final r = await SyncRig.create(
      photos: photosNamed({
        'mine-device': 'Screenshot_20261101_101010_Remine.jpg',
        'mine-sent': 'Screenshot_20261101_101011_Remine.jpg',
      }),
    );
    await r.state.setDeviceId(7);
    await r.state.putEntry(
      const SyncEntry(
        assetId: 'mine-device',
        modifiedAt: 1000,
        status: SyncStatusCode.deviceOnly,
      ),
    );
    await r.state.putEntry(
      const SyncEntry(
        assetId: 'mine-sent',
        modifiedAt: 1001,
        status: SyncStatusCode.synced,
      ),
    );

    await r.sync.run();

    final forget = r.client.sent
        .where((s) => s.path == '/api/screenshots/forget')
        .map((s) => s.utf8Text)
        .join();
    expect(forget, contains('mine-sent'), reason: '서버에 보냈던 것은 지운다');
    expect(forget, isNot(contains('mine-device')));
  });
}
