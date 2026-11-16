import 'category.dart';

/// 관심사 카드의 썸네일 한 장. 사진은 서버에 없어서 [localAssetId]로 기기 갤러리에서 읽는다.
class InterestCapture {
  const InterestCapture({
    required this.id,
    required this.localAssetId,
    this.takenAt,
  });

  /// 서버 캡처 id (Hero 태그·색 블록 seed).
  final int id;
  final String localAssetId;

  /// 촬영 시각. 휴지통 캡처를 뺀 뒤 마지막 캡처 날짜를 다시 셀 때 쓴다. 옛 응답에는 없어 null.
  final DateTime? takenAt;

  factory InterestCapture.fromJson(Map<String, dynamic> json) =>
      InterestCapture(
        id: (json['id'] as num).toInt(),
        localAssetId: json['localAssetId'] as String,
        takenAt: DateTime.tryParse(json['takenAt'] as String? ?? ''),
      );
}

/// 반복해서 캡처한 관심사 하나(전체 기간 같은 태그 3회 이상). GET /api/interests 의 `items[]`.
class Interest {
  const Interest({
    required this.tag,
    required this.category,
    required this.forgotten,
    required this.captureCount,
    required this.dormantDays,
    required this.peakMonth,
    required this.peakMonthCount,
    required this.latestMonth,
    required this.latestMonthCount,
    required this.recent,
    this.linkedTags = const [],
  });

  /// 서버 기본값(`remine.interest.recent-days`). 응답에 값이 없을 때 쓴다.
  static const defaultRecentDays = 30;

  /// '#' 없는 태그 이름 (예: "니트 가디건"). 카테고리 화면의 태그 필터로 그대로 쓴다.
  final String tag;

  /// 이 관심사를 눌렀을 때 열 카테고리 (사용자가 고친 카테고리 반영).
  final Category category;

  /// 서버 `status == FORGOTTEN`: 마지막 캡처가 recentDays(30일)를 넘었다. 아니면 "요즘 모으는 중".
  final bool forgotten;

  /// 전체 기간 장수.
  final int captureCount;

  /// 마지막 캡처 이후 지난 일수 ("N일째 잠자는 중").
  final int dormantDays;

  /// 캡처가 가장 많았던 달(1~12)과 그 달 장수. 잊은 관심사 멘트 "9월에 12번이나 캡처했어요."
  final int peakMonth;
  final int peakMonthCount;

  /// 마지막 캡처의 달(1~12)과 그 달 장수. 요즘 관심사 멘트 "11월에 5번이나 캡처했어요."
  final int latestMonth;
  final int latestMonthCount;

  /// 최근 캡처 최대 3장 (최신순). 카드 콜라주에 쓴다.
  final List<InterestCapture> recent;

  /// 같은 캡처에 함께 붙은 다른 관심사 태그. 머릿속 지도의 연결선. 옛 서버 응답에는 없어 빈 목록.
  final List<String> linkedTags;

  factory Interest.fromJson(Map<String, dynamic> json) => Interest(
    tag: json['tag'] as String,
    category: Category.fromJson(json['category'] as String),
    forgotten: json['status'] == 'FORGOTTEN',
    captureCount: (json['captureCount'] as num).toInt(),
    dormantDays: (json['dormantDays'] as num).toInt(),
    peakMonth: (json['peakMonth'] as num).toInt(),
    peakMonthCount: (json['peakMonthCount'] as num).toInt(),
    latestMonth: (json['latestMonth'] as num).toInt(),
    latestMonthCount: (json['latestMonthCount'] as num).toInt(),
    recent: [
      for (final c in json['recent'] as List)
        InterestCapture.fromJson(c as Map<String, dynamic>),
    ],
    linkedTags: [
      for (final t in json['linkedTags'] as List? ?? const []) t as String,
    ],
  );

  /// 휴지통 캡처를 뺀 복사본. 뺀 장수만큼 횟수를 줄이고, 마지막 캡처가 빠졌으면
  /// 남은 최신 캡처로 잠든 일수·상태([recentDays] 경계)를 다시 정한다.
  // ponytail: 아는 건 recent 3장뿐이라 달별 장수는 같은 달이면 1씩 빼는 근사치다. 서버에 휴지통이 알려지면 정확해진다.
  Interest without(Set<int> trashedIds, {int recentDays = defaultRecentDays}) {
    final removed = recent.where((c) => trashedIds.contains(c.id)).toList();
    if (removed.isEmpty) return this;
    final kept = recent.where((c) => !trashedIds.contains(c.id)).toList();
    final oldLatest = recent.first.takenAt;
    final newLatest = kept.firstOrNull?.takenAt;
    final moreDormant = oldLatest == null || newLatest == null
        ? 0
        : _days(newLatest, oldLatest);
    final dormant = dormantDays + moreDormant;
    int minus(int month, int count) =>
        (count - removed.where((c) => c.takenAt?.month == month).length).clamp(
          1,
          count,
        );
    return Interest(
      tag: tag,
      category: category,
      forgotten: dormant > recentDays,
      captureCount: captureCount - removed.length,
      dormantDays: dormant,
      peakMonth: peakMonth,
      peakMonthCount: minus(peakMonth, peakMonthCount),
      latestMonth: newLatest?.month ?? latestMonth,
      latestMonthCount: newLatest == null || newLatest.month == latestMonth
          ? minus(latestMonth, latestMonthCount)
          : kept.where((c) => c.takenAt?.month == newLatest.month).length,
      recent: kept,
      linkedTags: linkedTags,
    );
  }

  /// 달력 날짜 차이(시각 무시, 일광절약시간 영향 없게 UTC로).
  static int _days(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

/// 서버와 같은 순서: 잊고 있었던 관심사(장수↓ → 오래 안 본 순) → 요즘 모으는 중(장수↓ → 최근 순) → 태그 이름순.
List<Interest> sortInterests(List<Interest> list) => [...list]
  ..sort((a, b) {
    if (a.forgotten != b.forgotten) return a.forgotten ? -1 : 1;
    if (a.captureCount != b.captureCount) {
      return b.captureCount.compareTo(a.captureCount);
    }
    if (a.dormantDays != b.dormantDays) {
      return a.forgotten
          ? b.dormantDays.compareTo(a.dormantDays)
          : a.dormantDays.compareTo(b.dormantDays);
    }
    return a.tag.compareTo(b.tag);
  });
