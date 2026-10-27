import 'gallery_reader.dart';
import 'ocr_engine.dart';
import 'ocr_store.dart';
import 'ocr_temp_files.dart';
import 'own_capture.dart';
import 'privacy/app_rules.dart';
import 'privacy/local_verdict_store.dart';
import 'privacy/privacy_filter.dart';

/// 갤러리 읽기 → (파일명 판정) → 기기 안 OCR → (텍스트 판정) → 로컬 저장을 묶는다. 네트워크 호출은 없다.
///
/// 개인정보: 파일명으로 앱이 정해지면 OCR 자체를 건너뛰고, 민감 정보가 걸리면 본문을 저장하지 않으며,
/// 전화번호는 마스킹본만 저장한다. 로그·오류 메시지에는 원문이나 감지 값을 남기지 않는다.
class DeviceCaptureService {
  DeviceCaptureService({
    required this.reader,
    required this.ocr,
    required this.store,
    required this.temp,
    LocalVerdictStore? verdicts,
    this.foreground,
    DateTime Function()? now,
  }) : verdicts = verdicts ?? InMemoryLocalVerdictStore(),
       _now = now ?? DateTime.now;

  /// 앱이 한 번에 읽는 최대 장수.
  static const maxPhotos = 300;

  final GalleryReader reader;
  final OcrEngine ocr;
  final OcrStore store;
  final OcrTempFiles temp;
  final LocalVerdictStore verdicts;

  /// 앱이 앞에 있던 구간 기록(자기 캡처 판정). 없으면(테스트) 파일명 규칙만.
  final ForegroundLog? foreground;
  final DateTime Function() _now;

  /// 최신순 최대 [maxPhotos]장. Remine 자신의 스크린샷은 뺀다(분류 대상이 아니다).
  Future<List<GalleryPhoto>> recent(String albumId) async =>
      (await recentSplit(albumId)).mine;

  /// [recent]와 같은 범위를 (분류할 것, Remine 자기 캡처)로 나눈다. 판정은 [OwnCaptureRule].
  /// [ownBy]는 자기 캡처로 본 이유별 장수(디버그 로그용).
  Future<
    ({
      List<GalleryPhoto> mine,
      List<GalleryPhoto> own,
      Map<OwnReason, int> ownBy,
    })
  >
  recentSplit(String albumId) async {
    final rule = await foreground?.rule() ?? const OwnCaptureRule();
    final mine = <GalleryPhoto>[], own = <GalleryPhoto>[];
    final ownBy = {for (final r in OwnReason.values) r: 0};
    for (final p in await reader.recent(albumId, limit: maxPhotos)) {
      final reason = rule.reasonOf(p);
      if (reason == null) {
        mine.add(p);
      } else {
        own.add(p);
        ownBy[reason] = ownBy[reason]! + 1;
      }
    }
    return (mine: mine, own: own, ownBy: ownBy);
  }

  /// 앨범의 모든 사진(파일명 집계용). OCR은 하지 않는다.
  Future<List<GalleryPhoto>> all(String albumId) =>
      reader.recent(albumId, limit: 1 << 30);

  /// 저장된 OCR 결과와 판정 결과를 모두 지운다.
  Future<void> clearAll() async {
    await store.clear();
    await verdicts.clear();
  }

  /// [photos]를 차례로 처리한다. 이미 판정했고 사진이 바뀌지 않았으면 건너뛴다.
  /// 한 장이 실패해도 나머지는 계속한다(실패 수만 센다 — 오류 메시지에 원문이 없도록 내용은 남기지 않는다).
  Future<OcrRun> run(
    List<GalleryPhoto> photos, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final records = <OcrRecord>[];
    var failed = 0;
    var skipped = 0;
    var byApp = 0;
    await temp.clear();
    for (var i = 0; i < photos.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final photo = photos[i];
      if (isOwnAppCapture(photo.fileName)) {
        // 방어: 목록에서 이미 빠지지만, 어떤 경로로 와도 OCR·저장을 하지 않는다.
        skipped++;
        onProgress?.call(i + 1, photos.length);
        continue;
      }
      try {
        final saved = await verdicts.find(photo.id);
        final fresh = saved != null && saved.modifiedAt == photo.modifiedAt;
        final cached = await store.find(photo.id);
        if (fresh && saved.route == LocalRoute.deviceOnly) {
          if (cached != null) records.add(cached); // 본문은 이미 비어 있다
          skipped++;
        } else if (fresh &&
            cached != null &&
            cached.modifiedAt == photo.modifiedAt &&
            cached.engine == ocr.name) {
          records.add(cached);
          skipped++;
        } else {
          final byName = judgeByApp(photo.fileName);
          if (byName != null) {
            await store.remove(photo.id); // 예전에 읽은 본문이 있으면 지운다
            await _saveVerdict(photo, byName);
            byApp++;
          } else {
            records.add(await _recognize(photo));
          }
        }
      } catch (_) {
        failed++;
      }
      onProgress?.call(i + 1, photos.length);
    }
    return OcrRun(
      records: records,
      failed: failed,
      skipped: skipped,
      byApp: byApp,
    );
  }

  Future<void> _saveVerdict(GalleryPhoto photo, LocalVerdict v) =>
      verdicts.save(
        StoredVerdict.of(
          v,
          assetId: photo.id,
          takenAt: photo.takenAt,
          modifiedAt: photo.modifiedAt,
          now: _now(),
        ),
      );

  Future<OcrRecord> _recognize(GalleryPhoto photo) async {
    final bytes = await reader.bytes(photo.id);
    if (bytes == null) throw StateError('no bytes');
    final copy = await temp.write(bytes); // 앱 캐시의 복사본 — 원본 경로는 건드리지 않는다
    try {
      final raw = await ocr.recognize(copy);
      final verdict = judgeByText(raw);
      // 저장하는 본문: 기기에서 끝나는 캡처는 비우고, 전화번호는 마스킹본.
      final text = switch (verdict.route) {
        LocalRoute.deviceOnly => '',
        LocalRoute.textOnly => verdict.maskedText!,
        LocalRoute.normal => raw,
      };
      final record = OcrRecord(
        assetId: photo.id,
        fileName: photo.fileName,
        modifiedAt: photo.modifiedAt,
        text: text,
        charCount: OcrRecord.countChars(
          verdict.route == LocalRoute.deviceOnly ? raw : text,
        ),
        ocrAt: _now(),
        engine: ocr.name,
      );
      await store.save(record);
      await _saveVerdict(photo, verdict);
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
    this.byApp = 0,
  });

  final List<OcrRecord> records;
  final int failed;
  final int skipped;

  /// 파일명의 앱 이름으로 판정해 OCR을 건너뛴 장수.
  final int byApp;
}
