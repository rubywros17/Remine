import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remine/data/device/local_db.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/models/category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 실제 SQLite(sqflite_common_ffi)로 DB v1 → v2 업그레이드를 검증한다.
const _card = '4111 1111 1111 1111';
const _phone = '010-7777-8888';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('remine_db_');
    path = p.join(dir.path, 'remine_ocr.db');
  });
  tearDown(() => dir.delete(recursive: true));

  LocalDb open() =>
      LocalDb(path: path, factory: factory, now: () => DateTime(2026, 10, 21));

  /// 필터가 생기기 전(v1)의 DB 파일을 만든다.
  Future<void> createV1() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE ocr_result ('
          'asset_id TEXT PRIMARY KEY, file_name TEXT NOT NULL, '
          'date_modified INTEGER NOT NULL, text TEXT NOT NULL, '
          'char_count INTEGER NOT NULL, ocr_at INTEGER NOT NULL, '
          'engine TEXT NOT NULL)',
        ),
      ),
    );
    Future<void> row(String id, String file, String text) =>
        db.insert('ocr_result', {
          'asset_id': id,
          'file_name': file,
          'date_modified': 1000,
          'text': text,
          'char_count': OcrRecord.countChars(text),
          'ocr_at': 0,
          'engine': 'mlkit-korean',
        });
    await row('card', 'Screenshot_1.png', '카드번호 $_card 유효기간');
    await row('phone', 'Screenshot_2.png', '예약 문의 $_phone 입니다');
    await row('chat', 'Screenshot_20261019_120000_KakaoTalk.jpg', '내일 봐');
    await row('plain', 'Screenshot_3.png', '니트 가디건 39,000원');
    await db.close();
  }

  test('v1 DB를 열면 v2로 올라가며 기존 행이 필터를 다시 통과한다', () async {
    await createV1();
    final local = open();
    final ocr = SqfliteOcrStore(local);
    final verdicts = SqfliteLocalVerdictStore(local);

    expect((await ocr.find('card'))!.text, isEmpty);
    expect((await ocr.find('card'))!.charCount, greaterThan(0));
    expect((await ocr.find('phone'))!.text, '예약 문의 [전화번호] 입니다');
    expect((await ocr.find('chat'))!.text, isEmpty);
    expect((await ocr.find('plain'))!.text, '니트 가디건 39,000원');

    final card = (await verdicts.find('card'))!;
    expect(card.route, LocalRoute.deviceOnly);
    expect(card.hidden, isTrue);
    expect(card.reasons, ['CARD']);
    expect((await verdicts.find('phone'))!.route, LocalRoute.textOnly);
    expect((await verdicts.find('chat'))!.hidden, isFalse);
    expect((await verdicts.find('plain'))!.route, LocalRoute.normal);

    final db = await local.db;
    expect(await db.getVersion(), LocalDb.version);
    await local.close();
  });

  /// 서버 연동 전(v2)의 DB 파일: 동의 설정과 기기 판정이 들어 있다.
  Future<void> createV2() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE ocr_result (asset_id TEXT PRIMARY KEY, file_name TEXT NOT NULL, '
            'date_modified INTEGER NOT NULL, text TEXT NOT NULL, char_count INTEGER NOT NULL, '
            'ocr_at INTEGER NOT NULL, engine TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE local_verdict (local_id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'asset_id TEXT NOT NULL UNIQUE, taken_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, '
            'route TEXT NOT NULL, category TEXT, hidden INTEGER NOT NULL, reasons TEXT NOT NULL, '
            'decided_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('setting', {'key': 'image_consent', 'value': '1'});
          await db.insert('local_verdict', {
            'asset_id': 'chat1',
            'taken_at': 1,
            'modified_at': 1,
            'route': 'deviceOnly',
            'category': 'CHAT',
            'hidden': 0,
            'reasons': 'APP_MESSENGER',
            'decided_at': 1,
          });
        },
      ),
    );
    await db.close();
  }

  test('v2 DB를 열면 최신으로 올라가고 기존 설정·판정은 그대로, 서버 표가 생긴다', () async {
    await createV2();
    final local = open();
    final settings = SqfliteSettingsStore(local);
    final verdicts = SqfliteLocalVerdictStore(local);
    final remote = SqfliteRemoteStateStore(local);

    expect(await (await local.db).getVersion(), LocalDb.version);
    expect(await settings.imageConsent(), isTrue); // 동의 설정 유지
    expect((await verdicts.find('chat1'))!.category, Category.chat);

    // 새 표가 바로 쓸 수 있다: 기기 id, 첫 분석 여부, 매핑, 마지막 목록 캐시
    expect(await remote.deviceId(), isNull);
    await remote.setDeviceId(7);
    expect(await remote.firstSyncDone(), isFalse);
    await remote.setFirstSyncDone();
    await remote.putEntry(
      const SyncEntry(
        assetId: 'a1',
        modifiedAt: 5,
        status: SyncStatusCode.failed,
      ),
    );
    await remote.linkServerIds({'a1': 42});
    await remote.putCache('summary', '{"categories":[]}');
    await local.close();

    // 다시 열어도(업그레이드 이후 재실행) 값이 남아 있다.
    final again = open();
    final r2 = SqfliteRemoteStateStore(again);
    expect(await r2.deviceId(), 7);
    expect(await r2.firstSyncDone(), isTrue);
    final e = (await r2.entry('a1'))!;
    expect(
      (e.serverId, e.modifiedAt, e.status),
      (42, 5, SyncStatusCode.failed),
    );
    expect(await r2.failedCount(), 1);
    expect(await r2.cached('summary'), '{"categories":[]}');
    expect(await r2.cached('none'), isNull);
    // 서버 초기화로 재등록할 때: 서버 쪽 기록만 지우고 사용자가 정한 것·첫 분석 완료는 남긴다.
    final prefs = SqfliteSettingsStore(again);
    await prefs.setImageConsent(true);
    await prefs.setNotificationsEnabled(true);
    await r2.clear();
    expect(await r2.deviceId(), isNull);
    expect(await r2.cached('summary'), isNull);
    expect(await r2.entry('a1'), isNull);
    expect(await r2.firstSyncDone(), isTrue);
    expect(await prefs.imageConsent(), isTrue);
    expect(await prefs.notificationsEnabled(), isTrue);
    await again.close();
  });

  test('[디버그] 초기화는 고른 값만 지운다: 첫 실행 선택 / 튜토리얼 봤음', () async {
    final local = open();
    final settings = SqfliteSettingsStore(local);
    await settings.setImageConsent(true);
    await settings.setNotificationsEnabled(false);
    await settings.setSwipeTutorialSeen();
    await settings.setOwnCaptureLog('{"x":1}');

    await settings.clearFirstRunChoices();
    expect(await settings.imageConsent(), isNull);
    expect(await settings.notificationsEnabled(), isNull);
    expect(await settings.swipeTutorialSeen(), isTrue, reason: '튜토리얼 기록은 따로');
    expect(await settings.ownCaptureLog(), '{"x":1}', reason: '다른 기록은 그대로');

    await settings.clearSwipeTutorialSeen();
    expect(await settings.swipeTutorialSeen(), isFalse);
    await settings.setSwipeTutorialSeen(); // 지운 뒤 다시 저장해도 된다
    expect(await settings.swipeTutorialSeen(), isTrue);
    await local.close();
  });

  test('v1 DB도 한 번에 최신까지 올라간다', () async {
    await createV1();
    final local = open();
    await local.db;
    expect(await (await local.db).getVersion(), LocalDb.version);
    final remote = SqfliteRemoteStateStore(local);
    await remote.putCache('k', 'v');
    expect(await remote.cached('k'), 'v');
    await local.close();
  });

  /// 휴지통 기록 표 전(v4)의 DB 파일: 휴지통에 한 장(TRASHED), 되살리는 중인 한 장(RESTORING).
  /// [v5]면 크기 칸 없는 휴지통 기록 표(v5)까지 있다.
  Future<void> createV4({bool v5 = false}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: v5 ? 5 : 4,
        onCreate: (db, _) async {
          for (final sql in [
            'CREATE TABLE ocr_result (asset_id TEXT PRIMARY KEY, file_name TEXT NOT NULL, '
                'date_modified INTEGER NOT NULL, text TEXT NOT NULL, char_count INTEGER NOT NULL, '
                'ocr_at INTEGER NOT NULL, engine TEXT NOT NULL)',
            'CREATE TABLE local_verdict (local_id INTEGER PRIMARY KEY AUTOINCREMENT, '
                'asset_id TEXT NOT NULL UNIQUE, taken_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, '
                'route TEXT NOT NULL, category TEXT, hidden INTEGER NOT NULL, reasons TEXT NOT NULL, '
                'decided_at INTEGER NOT NULL)',
            'CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            'CREATE TABLE server_map (asset_id TEXT PRIMARY KEY, server_id INTEGER, '
                'modified_at INTEGER NOT NULL, status TEXT NOT NULL)',
            'CREATE TABLE server_cache (key TEXT PRIMARY KEY, json TEXT NOT NULL, saved_at INTEGER NOT NULL)',
            'CREATE TABLE trash (asset_id TEXT PRIMARY KEY, category TEXT NOT NULL, '
                'taken_at INTEGER NOT NULL, trashed_at INTEGER NOT NULL, on_server INTEGER NOT NULL, '
                'state TEXT NOT NULL, pending INTEGER NOT NULL)',
          ]) {
            await db.execute(sql);
          }
          Future<void> trash(String id, String state) => db.insert('trash', {
            'asset_id': id,
            'category': 'ETC',
            'taken_at': 1,
            'trashed_at': DateTime(2026, 10, 20).millisecondsSinceEpoch,
            'on_server': 1,
            'state': state,
            'pending': 0,
          });
          await trash('kept', 'TRASHED');
          await trash('back', 'RESTORING');
          if (v5) {
            await db.execute(
              'CREATE TABLE trash_log (asset_id TEXT PRIMARY KEY, trashed_at INTEGER NOT NULL)',
            );
            await db.insert('trash_log', {
              'asset_id': 'kept',
              'trashed_at': DateTime(2026, 10, 20).millisecondsSinceEpoch,
            });
          }
        },
      ),
    );
    await db.close();
  }

  test(
    'v4 → v6: 휴지통 기록 표가 생기고, 휴지통에 있던 캡처 날짜를 옮긴다(되살리는 중인 건 빼고, 크기는 모름)',
    () async {
      await createV4();
      final local = open();
      final trash = SqfliteTrashStore(local);

      expect(await (await local.db).getVersion(), LocalDb.version);
      expect(await trash.trashedSince(DateTime(2026, 10, 19)), [
        TrashLogEntry('kept', DateTime(2026, 10, 20)),
      ]);
      expect((await trash.all()).map((t) => t.assetId), [
        'kept',
      ], reason: '기존 휴지통 그대로');
      await local.close();
    },
  );

  test('v5 → v6: 기존 기록은 크기 없이 그대로, 새로 넣으면 크기가 같이 남는다', () async {
    await createV4(v5: true);
    final local = open();
    final trash = SqfliteTrashStore(local, sizeOf: (id) async => 2048);

    expect(await (await local.db).getVersion(), LocalDb.version);
    await trash.add(
      TrashedShot(
        assetId: 'new',
        category: Category.etc,
        takenAt: DateTime(2026, 1, 1),
        trashedAt: DateTime(2026, 10, 21),
        onServer: false,
      ),
    );
    expect((await trash.trashedSince(DateTime(2026, 10, 19))).toSet(), {
      TrashLogEntry('kept', DateTime(2026, 10, 20)),
      TrashLogEntry('new', DateTime(2026, 10, 21), 2048),
    });
    await local.close();
  });

  test('크기 채우기: 비어 있는 기록만 채우고 이미 있는 크기는 덮어쓰지 않는다', () async {
    await createV4(v5: true); // 'kept'는 크기 없이 옮겨진다
    final local = open();
    final trash = SqfliteTrashStore(local, sizeOf: (id) async => 500);
    await trash.add(
      TrashedShot(
        assetId: 'sized',
        category: Category.etc,
        takenAt: DateTime(2026, 1, 1),
        trashedAt: DateTime(2026, 10, 21),
        onServer: false,
      ),
    );
    await trash.fillSizes({'kept': 7000, 'sized': 9999, 'nobody': 1});

    expect((await trash.trashedSince(DateTime(2026, 10, 19))).toSet(), {
      TrashLogEntry('kept', DateTime(2026, 10, 20), 7000),
      TrashLogEntry('sized', DateTime(2026, 10, 21), 500),
    });
    await local.close();
  });

  test('새 설치(v6): 넣을 때 크기가 남고(못 읽으면 null), 갤러리에서 지워도 남고, 되살리면 빠진다', () async {
    final local = open();
    final trash = SqfliteTrashStore(
      local,
      sizeOf: (id) async => id == 'a' ? 1000 : throw StateError('못 읽음'),
    );
    TrashedShot shot(String id, int day) => TrashedShot(
      assetId: id,
      category: Category.etc,
      takenAt: DateTime(2026, 1, 1),
      trashedAt: DateTime(2026, 10, day),
      onServer: false,
    );
    await trash.add(shot('a', 19));
    await trash.add(shot('b', 20));
    await trash.add(shot('old', 1));
    await trash.markDeleted(['a']); // 휴지통 비우기(기기 전용이라 trash 행은 사라진다)
    await trash.restore('b');

    expect(await trash.trashedSince(DateTime(2026, 10, 19)), [
      TrashLogEntry('a', DateTime(2026, 10, 19), 1000),
    ]);
    expect(
      await trash.all(),
      hasLength(1),
      reason: 'old만 휴지통에(크기를 못 읽어도 넣어진다)',
    );
    await local.close();
  });

  test('업그레이드 뒤 DB 파일 바이트에 지운 원문이 남아 있지 않다', () async {
    await createV1();
    final local = open();
    await local.db; // 업그레이드 실행
    await local.close();

    final bytes = [
      for (final f in dir.listSync().whereType<File>()) ...f.readAsBytesSync(),
    ];
    final dump = latin1.decode(bytes);
    expect(dump, isNot(contains(_card)));
    expect(dump, isNot(contains('7777-8888')));
    expect(dump, contains('ocr_result')); // 파일을 제대로 읽었는지 확인
  });

  test('새 설치(v2 바로 생성)도 같은 표를 만든다', () async {
    final local = open();
    final verdicts = SqfliteLocalVerdictStore(local);
    final settings = SqfliteSettingsStore(local);

    expect(await settings.imageConsent(), isNull);
    await settings.setImageConsent(true);
    expect(await settings.imageConsent(), isTrue);
    await settings.setImageConsent(false);
    expect(await settings.imageConsent(), isFalse);

    StoredVerdict v(String id, LocalVerdict j, int min) => StoredVerdict.of(
      j,
      assetId: id,
      takenAt: DateTime(2026, 10, 19, 12, min),
      modifiedAt: 1,
      now: DateTime(2026, 10, 21),
    );
    await verdicts.save(v('a', judgeByText('카드 $_card'), 1));
    await verdicts.save(
      v('b', judgeByApp('Screenshot_20261019_120000_KakaoTalk.jpg')!, 2),
    );
    final firstId = (await verdicts.find('a'))!.localId;
    await verdicts.save(v('a', judgeByText('카드 $_card'), 3)); // 같은 asset → 덮어쓰기
    expect((await verdicts.find('a'))!.localId, firstId); // 번호 유지

    expect((await verdicts.deviceOnly(hidden: true)).map((x) => x.assetId), [
      'a',
    ]);
    expect((await verdicts.deviceOnly(hidden: false)).map((x) => x.assetId), [
      'b',
    ]);
    expect((await verdicts.deviceOnly()).length, 2);
    await local.close();
  });
}
