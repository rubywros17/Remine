import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_service.dart';
import 'package:remine/data/remote/sync_status.dart';

import 'support/fake_remote.dart';

// 예전 스크린샷(최신 300장보다 오래된 것)을 같은 동기화의 2단계로 하루 몫만큼 이어서 보내는지.
// 사진은 최신순 p0, p1, …(1분 간격). p0~p299가 최신 300장, p300부터가 예전 스크린샷이다.
const _recent = DeviceCaptureService.maxPhotos;

GalleryPhoto _photo(int i, {String? fileName}) => GalleryPhoto(
  id: 'p$i',
  fileName: fileName ?? 'Screenshot_$i.png',
  takenAt: DateTime(2026, 10, 19, 12).subtract(Duration(minutes: i)),
  modifiedAt: 1000 + i,
);

/// 예전 스크린샷 [older]장이 있는 갤러리. [names]로 특정 사진의 파일명을 바꾼다.
Future<SyncRig> _rig(
  int older, {
  Map<int, String> names = const {},
  Map<String, String> texts = const {},
  String olderRange = '',
  Future<bool> Function()? isWifi,
  Future<bool> Function()? isCharging,
}) async {
  final photos = [
    for (var i = 0; i < _recent + older; i++) _photo(i, fileName: names[i]),
  ];
  final rig = await SyncRig.create(
    photos: photos,
    texts: {for (final p in photos) p.id: '글자 ${p.id} 입니다', ...texts},
    consent: false, // 글자만 보낸다(이미지 경로는 이 테스트의 관심사가 아니다)
    olderRange: olderRange,
    isWifi: isWifi,
    isCharging: isCharging,
  );
  // 첫 동기화: 최신 300장을 보낸다. 옛 서버처럼 남은 몫을 주지 않으니 예전 단계는 돌지 않는다.
  await _sync(rig);
  rig.client.sent.clear();
  return rig;
}

/// 새 스크린샷 단계와, 그 뒤 따로 도는 예전 단계까지 끝날 때까지.
Future<void> _sync(SyncRig rig) async {
  await rig.sync.run();
  await rig.sync.olderIdle;
}

List<String> _sentIds(SyncRig rig) => [
  for (final r in rig.client.analyzeCalls)
    ...RegExp(r'"localAssetId":"([^"]+)"')
        .allMatches(r.utf8Text)
        .map((m) => m.group(1)!),
];

String? _cursorId(InMemorySettingsStore s) =>
    PhotoPosition.decode(s.cursor)?.id;

void main() {
  test('첫 동기화는 최신 300장만 보낸다(예전 스크린샷 없음)', () async {
    final rig = await SyncRig.create(
      photos: [for (var i = 0; i < _recent + 3; i++) _photo(i)],
      texts: {for (var i = 0; i < _recent + 3; i++) 'p$i': '글자 $i'},
      consent: false,
    );
    await _sync(rig);
    final ids = _sentIds(rig);
    expect(ids, hasLength(_recent));
    expect(ids, isNot(contains('p300')));
  });

  test('범위를 고르지 않았으면(기본) 남은 몫이 있어도 예전 스크린샷을 읽지 않는다', () async {
    final rig = await _rig(5);
    rig.client.olderRemaining = 100;

    await _sync(rig);

    expect(rig.reader.olderAsked, isEmpty);
    expect(_sentIds(rig), isEmpty);
    expect(rig.settings.cursor, isNull);
  });

  test('남은 몫만큼 최신 → 오래된 순으로 보내고, 다음 날 커서 뒤부터 이어간다', () async {
    final rig = await _rig(5);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 3;

    await _sync(rig);

    expect(_sentIds(rig), ['p300', 'p301', 'p302']);
    expect(_cursorId(rig.settings), 'p302');
    expect(rig.settings.quota?.remaining, 0);
    expect(
      rig.reader.olderAsked.single.$1?.id,
      'p299',
      reason: '커서가 비었으면 새 단계가 본 최신 목록의 가장 오래된 장부터(맨 앞 재확인 없음)',
    );

    // 다음 날: 몫이 다시 찼다
    rig.client.sent.clear();
    rig.client.olderRemaining = 3;
    await _sync(rig);

    expect(_sentIds(rig), ['p303', 'p304']);
    expect(_cursorId(rig.settings), 'p304');
    expect(rig.settings.quota?.remaining, 1);
  });

  test('한도에 걸린 장과 그 뒤는 커서를 넘기지 않고, 다음 날 그 장부터 다시 보낸다', () async {
    final rig = await _rig(5);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 5;
    rig.client.failWith['p302'] = 'DAILY_LIMIT_EXCEEDED';

    await _sync(rig);

    expect(_cursorId(rig.settings), 'p301', reason: 'p302에서 멈춘다');
    expect(await rig.state.entry('p302'), isNull, reason: '한도 장은 기록하지 않는다');

    rig.client.sent.clear();
    rig.client.failWith.clear();
    rig.client.olderRemaining = 5;
    await _sync(rig);

    expect(_sentIds(rig), ['p302'], reason: '이미 보낸 p303·p304는 건너뛴다');
    expect(_cursorId(rig.settings), 'p304');
  });

  test('분석에 실패한 장에서도 커서가 멈추고 다음에 다시 보낸다', () async {
    final rig = await _rig(3);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 10;
    rig.client.failWith['p301'] = 'LLM_CALL_FAILED';

    await _sync(rig);

    expect(_cursorId(rig.settings), 'p300');
    expect((await rig.state.entry('p301'))?.status, SyncStatusCode.failed);
  });

  /// 하루 몫을 채워 한 번 더 동기화한다(다음 날·다음 실행).
  Future<void> runAgain(SyncRig rig, {int remaining = 10}) async {
    rig.client.sent.clear();
    rig.client.olderRemaining = remaining;
    await _sync(rig);
  }

  test('같은 장이 2번 실패할 때까지는 커서가 멈추고, 3번째 실패하면 건너뛰고 지나간다', () async {
    final rig = await _rig(3);
    rig.settings.olderRange = olderRangeAll;
    rig.client.failWith['p301'] = 'LLM_CALL_FAILED';

    await runAgain(rig);
    expect(_cursorId(rig.settings), 'p300');
    expect(await rig.state.olderFailures('p301'), 1);

    await runAgain(rig);
    expect(_sentIds(rig), ['p301'], reason: '실패한 장만 다시 보낸다');
    expect(_cursorId(rig.settings), 'p300', reason: '2번까지는 멈춘다');
    expect(await rig.state.olderFailures('p301'), 2);

    await runAgain(rig);
    expect(_cursorId(rig.settings), 'p302', reason: '3번째 실패로 건너뛴다');
    expect(rig.state.olderFailureCounts, isEmpty, reason: '지나가면 기록을 지운다');

    await runAgain(rig);
    expect(_sentIds(rig), isEmpty, reason: '건너뛴 장을 다시 보내지 않는다');
  });

  test('하루 한도 초과는 실패 횟수에 세지 않는다', () async {
    final rig = await _rig(3);
    rig.settings.olderRange = olderRangeAll;
    rig.client.failWith['p301'] = 'DAILY_LIMIT_EXCEEDED';

    for (var i = 0; i < 3; i++) {
      await runAgain(rig);
    }
    expect(await rig.state.olderFailures('p301'), 0);
    expect(_cursorId(rig.settings), 'p300', reason: '한도에 걸린 장에서 계속 멈춘다');

    rig.client.failWith.clear();
    await runAgain(rig);
    expect(_sentIds(rig), ['p301']);
    expect(_cursorId(rig.settings), 'p302');
  });

  test('실패했다가 성공하면 실패 기록을 지운다', () async {
    final rig = await _rig(2);
    rig.settings.olderRange = olderRangeAll;
    rig.client.failWith['p301'] = 'LLM_INVALID_RESPONSE';
    await runAgain(rig);
    expect(await rig.state.olderFailures('p301'), 1);

    rig.client.failWith.clear();
    await runAgain(rig);

    expect(await rig.state.olderFailures('p301'), 0);
    expect(_cursorId(rig.settings), 'p301');
  });

  test('예전 스크린샷 단계가 예외를 던져도 새 스크린샷은 다 보내고 동기화는 정상으로 끝난다', () async {
    final lines = <String>[];
    final photos = [for (var i = 0; i < _recent + 3; i++) _photo(i)];
    final rig = await SyncRig.create(
      photos: photos,
      texts: {for (final p in photos) p.id: '글자 ${p.id}'},
      consent: false,
      log: lines.add,
    );
    await _sync(rig); // 첫 동기화(최신 300장)
    // 그 뒤 새로 2장을 찍었고, 예전 단계는 고장 났다
    final registered = (await rig.state.registeredAt())!;
    for (final id in ['n0', 'n1']) {
      rig.reader.photos.insert(
        0,
        GalleryPhoto(
          id: id,
          fileName: 'Screenshot_$id.png',
          takenAt: registered.add(const Duration(minutes: 1)),
          modifiedAt: 9000,
        ),
      );
      rig.ocr.textByAsset[id] = '새 글자 $id';
    }
    rig.client.sent.clear();
    lines.clear();
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 10;
    rig.reader.olderError = StateError('예전 단계 고장');

    await _sync(rig);

    expect(
      _sentIds(rig),
      unorderedEquals(['n0', 'n1']),
      reason: '새 스크린샷은 전송 완료',
    );
    expect(rig.status.issue, SyncIssue.none);
    expect(await rig.state.firstSyncDone(), isTrue);
    expect(lines.where((l) => l.startsWith('[sync] 중단')), isEmpty);
    // 기본은 예외 종류만(메시지에 OCR 원문이 섞일 수 있다)
    expect(
      lines.singleWhere((l) => l.startsWith('[older] 중단')),
      '[older] 중단: StateError',
    );
  });

  /// 기기 등록 뒤에 새로 찍은 사진 한 장을 갤러리 맨 앞에 넣는다.
  Future<void> addFresh(SyncRig rig, String id) async {
    final registered = (await rig.state.registeredAt())!;
    rig.reader.photos.insert(
      0,
      GalleryPhoto(
        id: id,
        fileName: 'Screenshot_$id.png',
        takenAt: registered.add(const Duration(minutes: 5)),
        modifiedAt: 9000,
      ),
    );
    rig.ocr.textByAsset[id] = '새 글자 $id';
  }

  test(
    '예전 단계 진행 중에 새 동기화가 오면 예전은 멈추고 새 스크린샷이 먼저 끝나며, 그 뒤 예전이 커서부터 이어간다',
    () async {
      final rig = await _rig(45);
      rig.settings.olderRange = olderRangeAll;
      rig.client.olderRemaining = 41; // 가짜 서버는 새 사진 n0도 몫에서 뺀다 → 예전 40장
      final gate = Completer<void>();
      rig.reader.olderGate = gate.future; // 예전 단계가 첫 쪽을 읽는 중에 붙잡힌다

      await rig.sync.run(); // 새 스크린샷 단계(보낼 것 없음)만 기다린다
      expect(rig.sync.isRunning, isFalse, reason: 'run()은 새 단계만 끝나면 완료');
      expect(rig.sync.isOlderRunning, isTrue, reason: '예전 단계는 따로 도는 중');

      await addFresh(rig, 'n0');
      await rig.sync.run(); // 예전 단계가 진행 중이어도 바로 새 동기화가 돈다
      expect(rig.sync.isRunning, isFalse);
      expect(_sentIds(rig), ['n0'], reason: '새 스크린샷이 먼저, 예전은 아직 하나도 안 갔다');

      rig.reader.olderGate = null;
      gate.complete(); // 붙잡힌 예전 단계: 읽은 쪽을 보내기 전에 멈춘다 → 새 단계 뒤에 다시 시작
      await rig.sync.olderIdle;

      final ids = _sentIds(rig);
      expect(ids.first, 'n0');
      expect(ids.skip(1), [for (var i = 300; i < 340; i++) 'p$i']);
      expect(
        ids.where((id) => id == 'p300'),
        hasLength(1),
        reason: '멈춘 쪽을 두 번 보내지 않는다',
      );
      expect(_cursorId(rig.settings), 'p339');
    },
  );

  test('앱이 뒤로 가면 예전 단계는 배치 사이에서 멈추고, 다시 앞으로 와서 동기화하면 이어간다', () async {
    final rig = await _rig(30);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 30;
    final gate = Completer<void>();
    rig.reader.olderGate = gate.future;

    await rig.sync.run();
    rig.sync.pauseOlder(); // 앱이 뒤로
    rig.reader.olderGate = null;
    gate.complete();
    await rig.sync.olderIdle;
    expect(_sentIds(rig), isEmpty);
    expect(rig.settings.cursor, isNull, reason: '보내지 않은 쪽은 커서를 넘기지 않는다');

    rig.sync.resumeOlder(); // 다시 앞으로
    await _sync(rig);
    expect(_sentIds(rig), hasLength(30));
    expect(_cursorId(rig.settings), 'p329');
  });

  test('예전 단계는 홈 갱신을 배치마다가 아니라 끝날 때 한 번 부른다', () async {
    final rig = await _rig(45);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 45; // 20 + 20 + 5장, 배치 세 번
    final before = rig.batches.length;

    await _sync(rig);

    expect(_sentIds(rig), hasLength(45));
    // 새 단계(보낼 것 없음)가 끝에서 한 번 + 예전 단계가 끝에서 한 번
    expect(rig.batches.length - before, 2);
  });

  test('예외 메시지·스택은 VERBOSE_ERRORS일 때만 남는다', () {
    final st = StackTrace.fromString(
      List.generate(30, (i) => '#$i frame$i').join('\n'),
    );
    final secret = StateError('OCR 원문 비밀');
    expect(SyncService.describeError(secret, st), 'StateError');
    final verbose = SyncService.describeError(secret, st, verbose: true);
    expect(verbose.split('\n').first, 'StateError: Bad state: OCR 원문 비밀');
    expect(verbose.split('\n'), hasLength(11), reason: '메시지 + 스택 앞 10줄');
  });

  test('VERBOSE_ERRORS로 켠 동기화만 [older] 중단 로그에 메시지를 남긴다', () async {
    final lines = <String>[];
    final photos = [for (var i = 0; i < _recent + 2; i++) _photo(i)];
    final rig = await SyncRig.create(
      photos: photos,
      texts: {for (final p in photos) p.id: '글자 ${p.id}'},
      consent: false,
      log: lines.add,
      verboseErrors: true,
    );
    await _sync(rig);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 10;
    rig.reader.olderError = StateError('예전 단계 고장');

    await _sync(rig);

    final older = lines.singleWhere((l) => l.startsWith('[older] 중단'));
    expect(older, startsWith('[older] 중단: StateError: Bad state: 예전 단계 고장\n'));
  });

  test('남은 몫이 0이면 그날은 읽지도 보내지도 않는다', () async {
    final rig = await _rig(5);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 0;

    await _sync(rig);

    expect(rig.reader.olderAsked, isEmpty);
    expect(_sentIds(rig), isEmpty);
    expect(rig.settings.quota?.remaining, 0);
  });

  test('응답의 남은 몫이 0이 되면 같은 실행 안에서도 바로 멈춘다', () async {
    final rig = await _rig(45); // 20장씩 읽으면 세 쪽
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 25;

    await _sync(rig);

    expect(_sentIds(rig), hasLength(25));
    expect(_cursorId(rig.settings), 'p324');
    // 최신 목록 끝(p299)부터 두 쪽: p300~p319, p320~p339(5장만 보내고 멈춤)
    expect(rig.reader.olderAsked.map((a) => a.$1?.id), ['p299', 'p319']);
  });

  test('Wi-Fi에서만(기본)이면 Wi-Fi가 아닐 때 건너뛰고, 끄면 보낸다', () async {
    var wifi = false;
    final rig = await _rig(2, isWifi: () async => wifi);
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 10;

    await _sync(rig);
    expect(_sentIds(rig), isEmpty);

    rig.settings.wifiOnly = false;
    await _sync(rig);
    expect(_sentIds(rig), ['p300', 'p301']);
  });

  test('충전 중일 때만이면 충전 중이 아닐 때 건너뛴다', () async {
    var charging = false;
    final rig = await _rig(2, isCharging: () async => charging);
    rig.settings.olderRange = olderRangeAll;
    rig.settings.chargingOnly = true;
    rig.client.olderRemaining = 10;

    await _sync(rig);
    expect(_sentIds(rig), isEmpty);

    charging = true;
    await _sync(rig);
    expect(_sentIds(rig), ['p300', 'p301']);
  });

  test('이어서 정리하기를 끄면 읽지 않는다', () async {
    final rig = await _rig(2);
    rig.settings.olderRange = olderRangeAll;
    rig.settings.enabled = false;
    rig.client.olderRemaining = 10;

    await _sync(rig);

    expect(rig.reader.olderAsked, isEmpty);
  });

  test('제외되는 장(자기 캡처·민감·글자 없음)은 보내지 않고 커서만 지나간다', () async {
    final rig = await _rig(
      4,
      names: {300: 'Screenshot_20261019_070000_Remine.jpg'},
      texts: {'p301': '카드 4111 1111 1111 1111', 'p302': ''},
    );
    rig.settings.olderRange = olderRangeAll;
    rig.client.olderRemaining = 10;

    await _sync(rig);

    expect(_sentIds(rig), ['p303']);
    expect(_cursorId(rig.settings), 'p303');
    expect(rig.client.olderRemaining, 9, reason: '보낸 1장만 몫을 쓴다');
  });

  test('범위를 줄여 커서가 새 범위 시작보다 오래됐으면 완료로 보고 읽지 않는다', () async {
    final rig = await _rig(2);
    rig.settings.olderRange = '2026-10-19';
    rig.settings.cursor = PhotoPosition(
      DateTime(2026, 10, 18, 23),
      'old',
    ).encode();
    rig.client.olderRemaining = 10;

    await _sync(rig);

    expect(rig.reader.olderAsked, isEmpty);
    expect(_sentIds(rig), isEmpty);
  });

  test('범위 시작을 갤러리 조회에 넘긴다', () async {
    final rig = await _rig(2);
    rig.settings.olderRange = '2026-10-19';
    rig.client.olderRemaining = 10;

    await _sync(rig);

    expect(rig.reader.olderAsked.first.$2, DateTime(2026, 10, 19));
    expect(_sentIds(rig), ['p300', 'p301']);
  });

  test('디버그 OLDER_RANGE는 범위를 고르지 않았을 때만 켠다', () async {
    final rig = await _rig(1, olderRange: '1y');
    rig.client.olderRemaining = 10;

    await _sync(rig);

    expect(_sentIds(rig), ['p300']);
    expect(rig.settings.olderRange, isNull, reason: '설정에 저장하지 않는다');
  });

  test('기기를 등록한 뒤에 생긴 사진은 300장을 넘어도 모두 새 스크린샷으로 보낸다', () async {
    final rig = await _rig(0);
    final registered = (await rig.state.registeredAt())!;
    // 등록 뒤에 302장을 더 찍었다 → 최신 300장 창을 넘는다
    final fresh = [
      for (var i = 0; i < 302; i++)
        GalleryPhoto(
          id: 'n$i',
          fileName: 'Screenshot_n$i.png',
          takenAt: registered.add(Duration(minutes: 302 - i)),
          modifiedAt: 5000 + i,
        ),
    ];
    rig.reader.photos.insertAll(0, fresh);
    for (final p in fresh) {
      rig.ocr.textByAsset[p.id] = '새 글자 ${p.id}';
    }

    await _sync(rig);

    expect(_sentIds(rig), hasLength(302));
    expect(rig.reader.sinceAsked.last, registered);
    expect(rig.reader.olderAsked, isEmpty);
  });

  test('olderRangeFromDefine은 일·달·해·전부를 날짜로 바꾼다', () {
    final now = DateTime(2026, 11, 18, 15);
    expect(olderRangeFromDefine('1y', now), '2025-11-18');
    expect(olderRangeFromDefine('6m', now), '2026-05-18');
    expect(olderRangeFromDefine('30d', now), '2026-10-19');
    expect(olderRangeFromDefine('all', now), olderRangeAll);
    expect(olderRangeFromDefine('', now), isNull);
    expect(olderRangeStart(null).enabled, isFalse);
    expect(olderRangeStart('2026-10-19').from, DateTime(2026, 10, 19));
  });

  test('같은 초에 찍힌 사진은 id로 순서를 정해 빠짐없이 지나간다', () {
    final t = DateTime(2026, 10, 19, 7);
    final cursor = PhotoPosition(t, '20');
    expect(PhotoPosition(t, '19').isOlderThan(cursor), isTrue);
    expect(PhotoPosition(t, '21').isOlderThan(cursor), isFalse);
    expect(PhotoPosition(t, '20').isOlderThan(cursor), isFalse);
    expect(PhotoPosition.decode(cursor.encode()), cursor);
    expect(PhotoPosition.decode('망가진 값'), isNull);
  });
}
