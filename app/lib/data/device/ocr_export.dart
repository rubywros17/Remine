import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ocr_store.dart';

/// 재측정용 JSON. **OCR 원문이 들어 있다** — 커밋하지 말고(.gitignore) 측정 뒤 폰·PC에서 지운다.
abstract final class OcrExport {
  static Map<String, Object?> build(
    List<OcrRecord> records, {
    required String engine,
    required DateTime exportedAt,
  }) => {
    'engine': engine,
    'exportedAt': exportedAt.toIso8601String(),
    'count': records.length,
    'items': [
      for (final r in records)
        {'fileName': r.fileName, 'charCount': r.charCount, 'text': r.text},
    ],
  };

  static String fileNameFor(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'ocr-export-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}.json';
  }

  static Future<File> write(
    Directory dir,
    List<OcrRecord> records, {
    required String engine,
    required DateTime now,
  }) async {
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileNameFor(now)));
    final json = build(records, engine: engine, exportedAt: now);
    return file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }
}
