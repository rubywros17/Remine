import 'category.dart';

/// 관심사 카드의 썸네일 한 장. 사진은 서버에 없어서 [localAssetId]로 기기 갤러리에서 읽는다.
class InterestCapture {
  const InterestCapture({required this.id, required this.localAssetId});

  /// 서버 캡처 id (Hero 태그·색 블록 seed).
  final int id;
  final String localAssetId;

  factory InterestCapture.fromJson(Map<String, dynamic> json) =>
      InterestCapture(
        id: (json['id'] as num).toInt(),
        localAssetId: json['localAssetId'] as String,
      );
}

/// 반복해서 캡처한 관심사 하나. GET /api/interests 의 `items[]`(+ 응답 맨 위 `windowDays`).
class Interest {
  const Interest({
    required this.tag,
    required this.category,
    required this.captureCount,
    required this.spanDays,
    required this.dormantDays,
    required this.recent,
    this.linkedTags = const [],
  });

  /// '#' 없는 태그 이름 (예: "니트 가디건"). 카테고리 화면의 태그 필터로 그대로 쓴다.
  final String tag;

  /// 이 관심사를 눌렀을 때 열 카테고리 (사용자가 고친 카테고리 반영).
  final Category category;

  /// 기간 동안 이 태그로 캡처한 횟수 (×N).
  final int captureCount;

  /// 집계 기간(일). 카드 문구 "2주 동안"의 근거.
  final int spanDays;

  /// 마지막 캡처 이후 지난 일수 ("N일째 잠자는 중").
  final int dormantDays;

  /// 최근 캡처 최대 3장 (최신순). 카드 콜라주에 쓴다.
  final List<InterestCapture> recent;

  /// 같은 캡처에 함께 붙은 다른 관심사 태그. 머릿속 지도의 연결선. 옛 서버 응답에는 없어 빈 목록.
  final List<String> linkedTags;

  /// 마지막 캡처 이후 이만큼 지나면 "잊은 관심사"(머릿속 지도에서 레몬색으로 깨어난다).
  static const forgottenAfterDays = 7;

  bool get forgotten => dormantDays >= forgottenAfterDays;

  /// [spanDays]는 항목이 아니라 응답 맨 위(`windowDays`)에 있어서 따로 받는다.
  factory Interest.fromJson(
    Map<String, dynamic> json, {
    required int spanDays,
  }) => Interest(
    tag: json['tag'] as String,
    category: Category.fromJson(json['category'] as String),
    captureCount: (json['captureCount'] as num).toInt(),
    spanDays: spanDays,
    dormantDays: (json['dormantDays'] as num).toInt(),
    recent: [
      for (final c in json['recent'] as List)
        InterestCapture.fromJson(c as Map<String, dynamic>),
    ],
    linkedTags: [
      for (final t in json['linkedTags'] as List? ?? const []) t as String,
    ],
  );

  /// 휴지통 캡처를 뺀 복사본. 뺀 장수만큼 횟수도 줄인다.
  Interest without(Set<int> trashedIds) {
    final kept = recent.where((c) => !trashedIds.contains(c.id)).toList();
    return Interest(
      tag: tag,
      category: category,
      captureCount: captureCount - (recent.length - kept.length),
      spanDays: spanDays,
      dormantDays: dormantDays,
      recent: kept,
      linkedTags: linkedTags,
    );
  }
}
