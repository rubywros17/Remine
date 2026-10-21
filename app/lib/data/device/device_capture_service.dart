import 'gallery_reader.dart';
import 'ocr_engine.dart';
import 'ocr_store.dart';
import 'ocr_temp_files.dart';

/// 갤러리 읽기 → 기기 안 OCR → 로컬 저장을 묶는다. 네트워크 호출은 없다.
class DeviceCaptureService {
  DeviceCaptureService({
    required this.reader,
    required this.ocr,
    required this.store,
    required this.temp,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 앱이 한 번에 읽는 최대 장수.
  static const maxPhotos = 300;

  final GalleryReader reader;
  final OcrEngine ocr;
  final OcrStore store;
  final OcrTempFiles temp;
  final DateTime Function() _now;

  Future<List<GalleryPhoto>> recent(String albumId) =>
      reader.recent(albumId, limit: maxPhotos);

  /// [photos]를 차례로 OCR한다. 이미 처리했고 사진이 바뀌지 않았으면 건너뛴다.
  /// 한 장이 실패해도 나머지는 계속한다(실패 수만 센다 — 오류 메시지에 원문이 없도록 내용은 남기지 않는다).
  Future<OcrRun> run(
    List<GalleryPhoto> photos, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final records = <OcrRecord>[];
    var failed = 0;
    var skipped = 0;
    await temp.clear();
    for (var i = 0; i < photos.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final photo = photos[i];
      try {
        final cached = await store.find(photo.id);
        if (cached != null &&
            cached.modifiedAt == photo.modifiedAt &&
            cached.engine == ocr.name) {
          records.add(cached);
          skipped++;
        } else {
          records.add(await _recognize(photo));
        }
      } catch (_) {
        failed++;
      }
      onProgress?.call(i + 1, photos.length);
    }
    return OcrRun(records: records, failed: failed, skipped: skipped);
  }

  Future<OcrRecord> _recognize(GalleryPhoto photo) async {
    final bytes = await reader.bytes(photo.id);
    if (bytes == null) throw StateError('no bytes');
    final copy = await temp.write(bytes); // 앱 캐시의 복사본 — 원본 경로는 건드리지 않는다
    try {
      final text = await ocr.recognize(copy);
      final record = OcrRecord(
        assetId: photo.id,
        fileName: photo.fileName,
        modifiedAt: photo.modifiedAt,
        text: text,
        charCount: OcrRecord.countChars(text),
        ocrAt: _now(),
        engine: ocr.name,
      );
      await store.save(record);
      return record;
    } finally {
      await temp.dispose(copy);
    }
  }
}

class OcrRun {
  const OcrRun({
    required this.records,
    required this.failed,
    required this.skipped,
  });

  final List<OcrRecord> records;
  final int failed;
  final int skipped;
}
