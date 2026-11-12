import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'ocr_migration.dart';
import 'ocr_store.dart';
import 'privacy/local_verdict_store.dart';

/// 기기 안 SQLite 한 파일. OCR 결과·판정 결과·설정 표가 같이 들어 있다.
///
/// 버전: 1 = `ocr_result`만, 2 = `local_verdict`·`setting` 추가 + 기존 OCR 행을 필터에 다시 통과,
/// 3 = `server_map`(asset id ↔ 서버 id·동기화 상태)·`server_cache`(마지막으로 받은 목록·요약) 추가,
/// 4 = `trash`(앱 휴지통과 서버 반영 대기열) 추가,
/// 5 = `trash_log`(휴지통에 넣은 날짜. 휴지통을 비워도 남아 정리 탭 "이번 주 비운 스크린샷"을 센다) 추가,
/// 6 = `trash_log.size`(넣을 때의 파일 크기, "이번 주 확보한 용량"). 그 전 기록은 null.
class LocalDb {
  /// [path]·[factory]는 테스트용(실제 SQLite 파일로 업그레이드를 검증). 기본은 앱 DB 폴더의 [fileName].
  LocalDb({
    this.fileName = 'remine_ocr.db',
    this.path,
    this.factory,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const version = 6;

  final String fileName;
  final String? path;
  final DatabaseFactory? factory;
  final DateTime Function() _now;
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final f = factory ?? databaseFactory;
    return f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), fileName),
      options: _options,
    );
  }

  OpenDatabaseOptions get _options => OpenDatabaseOptions(
    version: version,
    // 지운 내용이 빈 페이지에 남지 않게 한다(마이그레이션에서 본문을 비울 때 중요).
    onConfigure: (db) => db.rawQuery('PRAGMA secure_delete = ON'),
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE ocr_result ('
        'asset_id TEXT PRIMARY KEY, '
        'file_name TEXT NOT NULL, '
        'date_modified INTEGER NOT NULL, '
        'text TEXT NOT NULL, '
        'char_count INTEGER NOT NULL, '
        'ocr_at INTEGER NOT NULL, '
        'engine TEXT NOT NULL)',
      );
      await _createV2Tables(db);
      await _createV3Tables(db);
      await _createV4Tables(db);
      await _createV5Tables(db);
      await _createV6Columns(db);
    },
    onUpgrade: (db, from, to) async {
      if (from < 2) {
        await _createV2Tables(db);
        await _refilterExistingRows(db);
      }
      if (from < 3) await _createV3Tables(db);
      if (from < 4) await _createV4Tables(db);
      if (from < 5) {
        await _createV5Tables(db);
        // 이미 휴지통에 있던 캡처의 날짜를 옮겨 둔다(되살리는 중인 것은 뺀다).
        await db.execute(
          'INSERT OR IGNORE INTO trash_log (asset_id, trashed_at) '
          "SELECT asset_id, trashed_at FROM trash WHERE state != 'RESTORING'",
        );
      }
      if (from < 6) await _createV6Columns(db);
    },
  );

  static Future<void> _createV2Tables(Database db) async {
    await db.execute(
      'CREATE TABLE local_verdict ('
      'local_id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'asset_id TEXT NOT NULL UNIQUE, '
      'taken_at INTEGER NOT NULL, '
      'modified_at INTEGER NOT NULL, '
      'route TEXT NOT NULL, '
      'category TEXT, '
      'hidden INTEGER NOT NULL, '
      'reasons TEXT NOT NULL, '
      'decided_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static Future<void> _createV3Tables(Database db) async {
    await db.execute(
      'CREATE TABLE server_map ('
      'asset_id TEXT PRIMARY KEY, '
      'server_id INTEGER, '
      'modified_at INTEGER NOT NULL, '
      'status TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE server_cache ('
      'key TEXT PRIMARY KEY, '
      'json TEXT NOT NULL, '
      'saved_at INTEGER NOT NULL)',
    );
  }

  static Future<void> _createV4Tables(Database db) async {
    await db.execute(
      'CREATE TABLE trash ('
      'asset_id TEXT PRIMARY KEY, '
      'category TEXT NOT NULL, '
      'taken_at INTEGER NOT NULL, '
      'trashed_at INTEGER NOT NULL, '
      'on_server INTEGER NOT NULL, '
      'state TEXT NOT NULL, '
      'pending INTEGER NOT NULL)',
    );
  }

  /// 휴지통에 넣은 기록: asset id와 날짜뿐(카테고리·원문 없음). 되살리면 지운다.
  static Future<void> _createV5Tables(Database db) async {
    await db.execute(
      'CREATE TABLE trash_log ('
      'asset_id TEXT PRIMARY KEY, '
      'trashed_at INTEGER NOT NULL)',
    );
  }

  /// 휴지통에 넣을 때의 파일 크기(바이트). 크기 기록 전 행은 null로 남는다.
  static Future<void> _createV6Columns(Database db) =>
      db.execute('ALTER TABLE trash_log ADD COLUMN size INTEGER');

  Future<void> _refilterExistingRows(Database db) async {
    for (final row in await db.query('ocr_result')) {
      final r = refilterOcrRecord(ocrRecordFromRow(row), now: _now());
      if (r.record.text != ocrRecordFromRow(row).text) {
        await db.update(
          'ocr_result',
          {'text': r.record.text, 'char_count': r.record.charCount},
          where: 'asset_id = ?',
          whereArgs: [r.record.assetId],
        );
      }
      await db.insert('local_verdict', storedVerdictToRow(r.verdict));
    }
  }
}
