import 'category.dart';

/// 잊은 관심사(홈 카드). **임시 모델**: GET /api/interests 의 응답 형식이 spec에 아직 없어 앱에서 가정한 모양이다.
/// 서버 응답이 정해지면 이 모델을 맞춘다.
class Interest {
  const Interest({
    required this.tag,
    required this.category,
    required this.captureCount,
    required this.spanDays,
    required this.dormantDays,
    required this.screenshotIds,
  });

  /// '#' 없는 태그 이름 (예: "니트가디건").
  final String tag;

  /// 이 관심사를 눌렀을 때 열 카테고리.
  final Category category;

  /// 기간 동안 이 태그로 캡처한 횟수 (×N).
  final int captureCount;

  /// 집계 기간(일). 카드 문구 "2주 동안"의 근거.
  final int spanDays;

  /// 마지막 캡처 이후 지난 일수 ("N일째 잠자는 중").
  final int dormantDays;

  /// 카드 썸네일에 쓰는 캡처 id (최신순).
  final List<int> screenshotIds;
}
