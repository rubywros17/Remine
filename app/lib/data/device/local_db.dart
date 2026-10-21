import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'ocr_migration.dart';
import 'ocr_store.dart';
import 'privacy/local_verdict_store.dart';

/// 기기 안 SQLite 한 파일. OCR 결과·판정 결과·설정 표가 같이 들어 있다.
///
/// 버전: 1 = `ocr_result`만, 2 = `local_verdict`·`setting` 추가 + 기존 OCR 행을 필터에 다시 통과.
class LocalDb {
  /// [path]·[factory]는 테스트용(실제 SQLite 파일로 업그레이드를 검증). 기본은 앱 DB 폴더의 [fileName].
  LocalDb({
    this.fileName = 'remine_ocr.db',
    this.path,
    this.factory,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const version = 2;

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
    },
    onUpgrade: (db, from, to) async {
      if (from < 2) {
        await _createV2Tables(db);
        await _refilterExistingRows(db);
      }
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
