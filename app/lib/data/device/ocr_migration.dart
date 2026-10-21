import 'ocr_store.dart';
import 'privacy/privacy_filter.dart';
import 'privacy/local_verdict_store.dart';

/// 필터가 생기기 전에 저장된 OCR 행을 필터에 다시 통과시킨다(DB v1 → v2 마이그레이션).
/// - 기기에서 분류가 끝나는 캡처(민감 정보·메신저·금융 앱): 본문을 비운다.
/// - 전화번호가 있는 캡처: 본문을 마스킹본으로 바꾼다.
/// 판정 결과도 함께 돌려줘서 `local_verdict`에 넣는다.
///
/// 순수 함수라서 sqlite 없이 테스트한다. 원문·감지 값은 반환값에 남지 않는다.
({OcrRecord record, StoredVerdict verdict}) refilterOcrRecord(
  OcrRecord r, {
  required DateTime now,
}) {
  final v = judge(r.fileName, r.text);
  final text = switch (v.route) {
    LocalRoute.deviceOnly => '',
    LocalRoute.textOnly => v.maskedText!,
    LocalRoute.normal => r.text,
  };
  return (
    record: OcrRecord(
      assetId: r.assetId,
      fileName: r.fileName,
      modifiedAt: r.modifiedAt,
      text: text,
      charCount: v.route == LocalRoute.textOnly
          ? OcrRecord.countChars(text)
          : r.charCount,
      ocrAt: r.ocrAt,
      engine: r.engine,
    ),
    verdict: StoredVerdict.of(
      v,
      assetId: r.assetId,
      // ocr_result에는 촬영 시각이 없어 수정 시각으로 대신한다. 다음 실행에서 실제 촬영 시각으로 갱신된다.
      takenAt: DateTime.fromMillisecondsSinceEpoch(r.modifiedAt * 1000),
      modifiedAt: r.modifiedAt,
      now: now,
    ),
  );
}
