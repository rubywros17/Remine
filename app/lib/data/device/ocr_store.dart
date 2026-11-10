import 'package:sqflite/sqflite.dart';

import 'local_db.dart';

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

  /// asset id → 파일명(기록이 있는 것만). 목록 출처 표시용으로 한 번에 묶어 읽는다(원문은 읽지 않는다).
  Future<Map<String, String>> fileNames(List<String> assetIds);
  Future<void> save(OcrRecord record);
  Future<void> remove(String assetId);
  Future<int> count();
  Future<void> clear();
}

OcrRecord ocrRecordFromRow(Map<String, Object?> r) => OcrRecord(
  assetId: r['asset_id'] as String,
  fileName: r['file_name'] as String,
  modifiedAt: r['date_modified'] as int,
  text: r['text'] as String,
  charCount: r['char_count'] as int,
  ocrAt: DateTime.fromMillisecondsSinceEpoch(r['ocr_at'] as int),
  engine: r['engine'] as String,
);

/// 로컬 SQLite 저장. DB 파일은 앱 내부 저장소에 있고, 자동 백업은 꺼져 있다(`allowBackup=false`).
/// 민감한 캡처의 본문은 [DeviceCaptureService]가 비운 뒤에 들어온다(이 저장소는 받은 그대로 저장한다).
class SqfliteOcrStore implements OcrStore {
  SqfliteOcrStore(this._local);

  final LocalDb _local;

  @override
  Future<OcrRecord?> find(String assetId) async {
    final rows = await (await _local.db).query(
      'ocr_result',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
    return rows.isEmpty ? null : ocrRecordFromRow(rows.first);
  }

  @override
  Future<Map<String, String>> fileNames(List<String> assetIds) async {
    final db = await _local.db;
    final out = <String, String>{};
    // SQLite 변수 개수 상한(999) 아래로 나눠 묻는다.
    for (var i = 0; i < assetIds.length; i += 500) {
      final ids = assetIds.skip(i).take(500).toList();
      final rows = await db.query(
        'ocr_result',
        columns: ['asset_id', 'file_name'],
        where: 'asset_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
      );
      for (final r in rows) {
        out[r['asset_id'] as String] = r['file_name'] as String;
      }
    }
    return out;
  }

  @override
  Future<void> save(OcrRecord r) async {
    await (await _local.db).insert('ocr_result', {
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
  Future<void> remove(String assetId) async => (await _local.db).delete(
    'ocr_result',
    where: 'asset_id = ?',
    whereArgs: [assetId],
  );

  @override
  Future<int> count() async => Sqflite.firstIntValue(
    await (await _local.db).rawQuery('SELECT COUNT(*) FROM ocr_result'),
  )!;

  @override
  Future<void> clear() async => (await _local.db).delete('ocr_result');
}

/// 테스트·크롬용 메모리 저장소.
class InMemoryOcrStore implements OcrStore {
  final Map<String, OcrRecord> _rows = {};

  @override
  Future<OcrRecord?> find(String assetId) async => _rows[assetId];

  @override
  Future<Map<String, String>> fileNames(List<String> assetIds) async => {
    for (final id in assetIds)
      if (_rows[id] case final r?) id: r.fileName,
  };

  @override
  Future<void> save(OcrRecord record) async => _rows[record.assetId] = record;

  @override
  Future<void> remove(String assetId) async => _rows.remove(assetId);

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<void> clear() async => _rows.clear();
}
