import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 사진 한 장의 OCR 결과. 원문이 들어 있으니 기기 밖으로 내보내지 않는다(디버그 내보내기 제외).
class OcrRecord {
  const OcrRecord({
    required this.assetId,
    required this.fileName,
    required this.modifiedAt,
    required this.text,
    required this.charCount,
    required this.ocrAt,
    required this.engine,
  });

  final String assetId;
  final String fileName;
  final int modifiedAt;
  final String text;

  /// 공백을 뺀 글자 수 (spec의 OCR 기준값과 같은 기준).
  final int charCount;
  final DateTime ocrAt;
  final String engine;

  static int countChars(String text) =>
      text.replaceAll(RegExp(r'\s'), '').runes.length;
}

abstract interface class OcrStore {
  Future<OcrRecord?> find(String assetId);
  Future<void> save(OcrRecord record);
  Future<int> count();
  Future<void> clear();
}

/// 로컬 SQLite 저장. DB 파일은 앱 내부 저장소에 있고, 자동 백업은 꺼져 있다(`allowBackup=false`).
class SqfliteOcrStore implements OcrStore {
  SqfliteOcrStore({this.fileName = 'remine_ocr.db'});

  final String fileName;
  Database? _db;

  Future<Database> _open() async => _db ??= await openDatabase(
    p.join(await getDatabasesPath(), fileName),
    version: 1,
    onCreate: (db, _) => db.execute(
      'CREATE TABLE ocr_result ('
      'asset_id TEXT PRIMARY KEY, '
      'file_name TEXT NOT NULL, '
      'date_modified INTEGER NOT NULL, '
      'text TEXT NOT NULL, '
      'char_count INTEGER NOT NULL, '
      'ocr_at INTEGER NOT NULL, '
      'engine TEXT NOT NULL)',
    ),
  );

  @override
  Future<OcrRecord?> find(String assetId) async {
    final rows = await (await _open()).query(
      'ocr_result',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return OcrRecord(
      assetId: r['asset_id'] as String,
      fileName: r['file_name'] as String,
      modifiedAt: r['date_modified'] as int,
      text: r['text'] as String,
      charCount: r['char_count'] as int,
      ocrAt: DateTime.fromMillisecondsSinceEpoch(r['ocr_at'] as int),
      engine: r['engine'] as String,
    );
  }

  @override
  Future<void> save(OcrRecord r) async {
    await (await _open()).insert('ocr_result', {
      'asset_id': r.assetId,
      'file_name': r.fileName,
      'date_modified': r.modifiedAt,
      'text': r.text,
      'char_count': r.charCount,
      'ocr_at': r.ocrAt.millisecondsSinceEpoch,
      'engine': r.engine,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> count() async => Sqflite.firstIntValue(
    await (await _open()).rawQuery('SELECT COUNT(*) FROM ocr_result'),
  )!;

  @override
  Future<void> clear() async => (await _open()).delete('ocr_result');
}

/// 테스트·크롬용 메모리 저장소.
class InMemoryOcrStore implements OcrStore {
  final Map<String, OcrRecord> _rows = {};

  @override
  Future<OcrRecord?> find(String assetId) async => _rows[assetId];

  @override
  Future<void> save(OcrRecord record) async => _rows[record.assetId] = record;

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<void> clear() async => _rows.clear();
}
