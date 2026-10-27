import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/own_capture.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/remote/remote_state_store.dart';

import 'support/fake_remote.dart';

final _t0 = DateTime(2026, 10, 26, 15, 10); // 앱이 앞으로 온 시각

GalleryPhoto _shot(String id, String fileName, DateTime takenAt) =>
    GalleryPhoto(id: id, fileName: fileName, takenAt: takenAt, modifiedAt: 1);

GalleryPhoto _nameless(String id, DateTime at) =>
    _shot(id, 'Screenshot_${_stamp(at)}.jpg', at);

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

void main() {
  group('자기 캡처 규칙: 앱 이름 없음 + 앱이 앞에 있던 구간 안', () {
    final rule = OwnCaptureRule(
      intervals: [(_t0, _t0.add(const Duration(minutes: 10)))],
    );
    final end = _t0.add(const Duration(minutes: 10));

    test('구간 안이면 자기 캡처, 밖이면 아니다', () {
      expect(
        rule.isOwn(_nameless('a', _t0.add(const Duration(minutes: 3)))),
        isTrue,
      );
      expect(
        rule.isOwn(_nameless('b', _t0.subtract(const Duration(hours: 1)))),
        isFalse,
      );
      expect(
        rule.isOwn(_nameless('c', end.add(const Duration(hours: 1)))),
        isFalse,
      );
    });

    test('앞뒤 5초 여유: 5초까지는 자기 캡처, 6초면 아니다', () {
      expect(
        rule.isOwn(_nameless('a', _t0.subtract(const Duration(seconds: 5)))),
        isTrue,
      );
      expect(
        rule.isOwn(_nameless('b', end.add(const Duration(seconds: 5)))),
        isTrue,
      );
      expect(
        rule.isOwn(_nameless('c', _t0.subtract(const Duration(seconds: 6)))),
        isFalse,
      );
      expect(
        rule.isOwn(_nameless('d', end.add(const Duration(seconds: 6)))),
        isFalse,
      );
    });

    test('다른 앱 이름이 붙은 캡처는 구간 안이어도 아니고, Remine 이름은 구간 밖이어도 자기 캡처', () {
      final inside = _t0.add(const Duration(minutes: 3));
      expect(
        rule.isOwn(
          _shot('a', 'Screenshot_${_stamp(inside)}_Chrome.jpg', inside),
        ),
        isFalse,
      );
      expect(
        rule.isOwn(
          _shot('b', 'Screenshot_20250101_101010_Remine.jpg', DateTime(2025)),
        ),
        isTrue,
      );
    });

    test('1회 정리 기간(설치 ~ 업데이트) 안의 이름 없는 캡처는 자기 캡처, 그 뒤는 구간 규칙만', () {
      final r = OwnCaptureRule(
        backfill: (DateTime(2026, 10, 20, 15), DateTime(2026, 10, 26, 9)),
      );
      expect(r.isOwn(_nameless('a', DateTime(2026, 10, 22, 14))), isTrue);
      expect(
        r.isOwn(_nameless('b', DateTime(2026, 10, 19, 14))),
        isFalse,
        reason: '설치 전',
      );
      expect(
        r.isOwn(_nameless('c', DateTime(2026, 10, 26, 12))),
        isFalse,
        reason: '업데이트 뒤',
      );
    });
  });

  group('앱이 앞에 있던 구간 기록', () {
    late DateTime now;
    late InMemorySettingsStore settings;
    ForegroundLog log() => ForegroundLog(settings, now: () => now);

    setUp(() {
      now = _t0;
      settings = InMemorySettingsStore();
    });

    test('resumed ~ paused를 구간으로 남기고, 앞에 있는 동안은 지금까지로 본다', () async {
      final l = log();
      await l.resumed();
      now = _t0.add(const Duration(minutes: 2));
      expect((await l.rule()).intervals.single, (_t0, now));
      await l.paused();
      now = _t0.add(const Duration(hours: 1));
      expect((await l.rule()).intervals.single, (
        _t0,
        _t0.add(const Duration(minutes: 2)),
      ));
    });

    test('90일 지난 구간은 지운다', () async {
      final l = log();
      await l.resumed();
      now = now.add(const Duration(minutes: 1));
      await l.paused();
      now = now.add(const Duration(days: 91));
      await l.resumed();
      now = now.add(const Duration(minutes: 1));
      await l.paused();
      expect((await l.rule()).intervals, hasLength(1));
    });

    test('앞에 있다가 앱이 죽으면 다음 실행에서 시작 + 30분까지로 닫는다', () async {
      await log().resumed();
      now = _t0.add(const Duration(days: 1));
      final next = log(); // 새 실행
      await next.resumed();
      final intervals = (await next.rule()).intervals;
      expect(intervals.first, (_t0, _t0.add(ForegroundLog.staleCap)));
      expect(intervals.last.$1, now);
    });

    test('1회 정리 기간은 처음 정한 그대로(다음 실행에서 늘어나지 않는다)', () async {
      final installed = DateTime(2026, 10, 20, 15);
      await log().ensureBackfill(installed);
      now = _t0.add(const Duration(days: 3));
      await log().ensureBackfill(installed);
      expect((await log().rule()).backfill, (installed, _t0));
    });

    test('기록은 시각 숫자뿐이다(파일명·사진 id 없음)', () async {
      final l = log();
      await l.resumed();
      await l.paused();
      final saved = jsonDecode((await settings.ownCaptureLog())!) as Map;
      expect(saved.keys, unorderedEquals(['intervals', 'open', 'backfill']));
    });
  });

  group('이미 서버에 올라간 자기 캡처 정리', () {
    test(
      '예전에 보낸 자기 캡처는 forget으로 한 번 지우고, 다음 동기화에서는 다시 보내지도 지우지도 않는다',
      () async {
        final settings = InMemorySettingsStore();
        final log = ForegroundLog(
          settings,
          now: () => DateTime(2026, 10, 26, 9),
        );
        await log.ensureBackfill(DateTime(2026, 10, 20, 15));
        final rig = await SyncRig.create(
          photos: [
            _nameless('own', DateTime(2026, 10, 22, 14)), // 설치 뒤 · 업데이트 전
            _nameless('other', DateTime(2026, 10, 19, 14)), // 설치 전 다른 앱
            _shot(
              'chrome',
              'Screenshot_20261022_140000_Chrome.jpg',
              DateTime(2026, 10, 22, 14),
            ),
          ],
          texts: {'own': '우리 앱 화면', 'other': '글자 ' * 60, 'chrome': '글자 ' * 60},
          foreground: log,
        );
        // 규칙이 생기기 전에 보냈던 기록
        await rig.state.putEntry(
          const SyncEntry(
            assetId: 'own',
            modifiedAt: 1,
            status: SyncStatusCode.synced,
          ),
        );

        await rig.sync.run();
        final forgets = rig.client.sent.where(
          (r) => r.path == '/api/screenshots/forget',
        );
        expect(forgets.single.utf8Text, '{"assetIds":["own"]}');
        expect(await rig.state.entry('own'), isNull);
        expect(rig.ocr.recognized, unorderedEquals(['other', 'chrome']));
        final analyzed = rig.client.analyzeCalls.map((r) => r.utf8Text).join();
        expect(analyzed, isNot(contains('"own"')));

        await rig.sync.run();
        expect(
          rig.client.sent.where((r) => r.path == '/api/screenshots/forget'),
          hasLength(1),
          reason: '1회성 정리가 다시 돌지 않는다',
        );
        expect(
          rig.client.analyzeCalls.map((r) => r.utf8Text).join(),
          isNot(contains('"own"')),
        );
      },
    );
  });

  group('재전송 대상: 정리 기간·SYNC_LIMIT', () {
    Future<ForegroundLog> backfilled() async {
      final log = ForegroundLog(
        InMemorySettingsStore(),
        now: () => DateTime(2026, 10, 26, 9),
      );
      await log.ensureBackfill(DateTime(2026, 10, 20, 15));
      return log;
    }

    GalleryPhoto insta(String id, DateTime at) =>
        _shot(id, 'Screenshot_${_stamp(at)}_Instagram.jpg', at);

    test('1회 정리 기간 안이라도 이름 있는 캡처(인스타)는 보내고, 이름 없는 것만 뺀다', () async {
      final at = DateTime(2026, 10, 22, 14);
      final rig = await SyncRig.create(
        photos: [
          insta('i1', at),
          _nameless('own', at.add(const Duration(minutes: 1))),
          insta('i2', at.add(const Duration(minutes: 2))),
        ],
        texts: {'i1': '글자 ' * 60, 'i2': '글자 ' * 60, 'own': '우리 앱'},
        foreground: await backfilled(),
      );

      await rig.sync.run();

      final body = rig.client.analyzeCalls.map((r) => r.utf8Text).join();
      expect(body, contains('"i1"'));
      expect(body, contains('"i2"'));
      expect(body, isNot(contains('"own"')));
    });

    test('SYNC_LIMIT는 자기 캡처·이미 보낸 것을 빼고 남은 후보에서 센다', () async {
      final at = DateTime(2026, 10, 22, 14);
      final photos = [
        for (var k = 0; k < 6; k++)
          insta('i$k', at.subtract(Duration(minutes: k))),
        _nameless('own1', at.subtract(const Duration(hours: 1))),
        _nameless('own2', at.subtract(const Duration(hours: 2))),
      ];
      final logs = <String>[];
      final rig = await SyncRig.create(
        photos: photos,
        texts: {for (final p in photos) p.id: '글자 ' * 60},
        foreground: await backfilled(),
        photoLimit: 3,
        log: logs.add,
      );
      for (final id in ['i0', 'i1']) {
        await rig.state.putEntry(
          SyncEntry(assetId: id, modifiedAt: 1, status: SyncStatusCode.synced),
        );
      }

      await rig.sync.run();

      final body = rig.client.analyzeCalls.map((r) => r.utf8Text).join();
      for (final id in ['i2', 'i3', 'i4']) {
        expect(body, contains('"$id"'), reason: id);
      }
      expect(body, isNot(contains('"i5"')), reason: '후보 4장 중 최신 3장만');
      expect(
        logs,
        contains(
          '[sync] 대상 갤러리 8 → 자기 캡처 2(이름 0 · 앞에 있던 구간 0 · 1회 정리 기간 2)'
          ' → 이미 보냄 2 → 보낼 후보 4 → SYNC_LIMIT 후 3',
        ),
      );
      expect(logs.any((l) => l.startsWith('[sync] 결과 보냄 3 ')), isTrue);
      expect(logs.join(), isNot(contains('Screenshot_')), reason: '파일명 없음');
      expect(logs.join(), isNot(contains('i2')), reason: 'asset id 없음');
    });

    test('재등록으로 기록이 지워지면 SYNC_LIMIT만큼 다시 보낸다', () async {
      final at = DateTime(2026, 10, 22, 14);
      final photos = [
        for (var k = 0; k < 5; k++)
          insta('i$k', at.subtract(Duration(minutes: k))),
      ];
      final rig = await SyncRig.create(
        photos: photos,
        texts: {for (final p in photos) p.id: '글자 ' * 60},
        photoLimit: 4,
      );
      await rig.sync.run();
      expect(rig.client.analyzeCalls, isNotEmpty);
      await rig.state.clear(); // 서버가 기기를 잊음 → 전송 기록 비움
      await rig.state.setDeviceId(7);
      final before = rig.client.analyzeCalls.length;

      await rig.sync.run();

      final again = rig.client.analyzeCalls
          .skip(before)
          .map((r) => r.utf8Text)
          .join();
      for (final id in ['i0', 'i1', 'i2', 'i3']) {
        expect(again, contains('"$id"'), reason: id);
      }
    });
  });
}
