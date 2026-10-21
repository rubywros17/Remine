import '../device/privacy/local_verdict_store.dart';
import '../device/privacy/privacy_filter.dart';

/// 한 장을 서버에 어떻게 처리할지.
enum PlanAction {
  /// 서버로 보내지 않는다(기기에서 이미 분류했거나 판정이 없다).
  skip,

  /// 텍스트만 보낸다.
  sendText,

  /// 텍스트 + 축소 이미지를 보낸다(이미지를 못 만들면 [PlanEntry.fallback]을 따른다).
  sendWithImage,

  /// 글자가 없고 이미지도 못 보낸다 → 서버에 보내지 않고 기기에서 ETC로 분류한다.
  deviceEtc,
}

/// [PlanAction.sendWithImage]에서 이미지를 만들지 못했을 때의 대안.
enum ImageFallback { sendText, deviceEtc }

class PlanInput {
  const PlanInput({
    required this.assetId,
    required this.takenAt,
    required this.fileName,
    required this.text,
    required this.charCount,
    required this.verdict,
  });

  final String assetId;
  final DateTime takenAt;

  /// 판정에만 쓴다. 계획 결과([PlanEntry])에는 들어가지 않는다 — 파일명은 서버로 가지 않는다.
  final String fileName;
  final String text;
  final int charCount;

  /// 저장된 판정. 없으면 보내지 않는다.
  final StoredVerdict? verdict;
}

class PlanEntry {
  const PlanEntry({
    required this.assetId,
    required this.takenAt,
    required this.action,
    this.text = '',
    this.fallback = ImageFallback.deviceEtc,
  });

  final String assetId;
  final DateTime takenAt;
  final PlanAction action;

  /// 보낼 텍스트. 전화번호는 이미 가려져 있다. [PlanAction.skip]·[PlanAction.deviceEtc]에서는 비어 있다.
  final String text;
  final ImageFallback fallback;
}

/// 서버로 보낼 것을 정하는 **유일한 곳**. 보내면 안 되는 캡처는 여기서 [PlanAction.skip]이 되어 요청에 실릴 수 없다.
///
/// 규칙
/// - 기기에서 분류가 끝난 캡처(메신저·금융 앱, 강한 민감 정보)는 절대 보내지 않는다.
/// - 전화번호가 있으면 가린 텍스트만 보낸다(이미지 없음).
/// - 일반 캡처는 글자 수 < [thresholdChars]이고 이미지 동의가 켜졌을 때만 이미지를 붙인다.
/// - 저장된 판정을 믿되, 파일명·텍스트로 **다시 판정**해 더 엄격한 쪽을 따른다(규칙이 바뀐 뒤의 오래된 판정 방어).
PlanEntry planFor(
  PlanInput input, {
  required bool imageConsent,
  required int thresholdChars,
}) {
  PlanEntry skip() => PlanEntry(
    assetId: input.assetId,
    takenAt: input.takenAt,
    action: PlanAction.skip,
  );

  final stored = input.verdict;
  if (stored == null || stored.route == LocalRoute.deviceOnly) return skip();

  final fresh = judge(input.fileName, input.text);
  if (fresh.route == LocalRoute.deviceOnly) return skip();

  if (stored.route == LocalRoute.textOnly ||
      fresh.route == LocalRoute.textOnly) {
    // 저장된 본문은 이미 가려져 있다. 다시 판정이 번호를 찾았다면 가린 본문을 쓴다.
    return PlanEntry(
      assetId: input.assetId,
      takenAt: input.takenAt,
      action: PlanAction.sendText,
      text: fresh.maskedText ?? input.text,
    );
  }

  final wantsImage = imageConsent && input.charCount < thresholdChars;
  if (wantsImage) {
    return PlanEntry(
      assetId: input.assetId,
      takenAt: input.takenAt,
      action: PlanAction.sendWithImage,
      text: input.text,
      fallback: input.charCount == 0
          ? ImageFallback.deviceEtc
          : ImageFallback.sendText,
    );
  }
  if (input.charCount == 0) {
    return PlanEntry(
      assetId: input.assetId,
      takenAt: input.takenAt,
      action: PlanAction.deviceEtc,
    );
  }
  return PlanEntry(
    assetId: input.assetId,
    takenAt: input.takenAt,
    action: PlanAction.sendText,
    text: input.text,
  );
}
