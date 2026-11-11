import '../core/tokens.dart';
import '../models/category.dart';
import '../models/screenshot_item.dart';

/// 정리 탭의 "지워도 될 만한 캡처" 묶음. **기기 안에서만** 계산하고 서버로 아무것도 보내지 않는다.
///
/// - 석 달째 안 봄: 찍은 지 [AppTidy.staleDays]일이 넘은 캡처
/// - 갈 곳 없는 캡처: 카테고리 기타. 민감 정보로 숨긴 캡처는 저장소가 처음부터 목록에서 뺀다
/// - 쌍둥이 캡처: 거의 같은 캡처 묶음. 묶음마다 가장 최근 1장은 남긴다
/// 휴지통에 있거나 "분석 제외"한 캡처는 모든 묶음에서 빠진다.
class TidyBundles {
  const TidyBundles({
    required this.stale,
    required this.etc,
    this.twins = const [],
    this.twinsReady = false,
  });

  static const empty = TidyBundles(stale: [], etc: []);

  final List<ScreenshotItem> stale;
  final List<ScreenshotItem> etc;

  /// 쌍둥이 묶음. 묶음마다 최신순이고, 첫 장(가장 최근)은 남길 장이다.
  final List<List<ScreenshotItem>> twins;

  /// 쌍둥이 찾기를 지원하는지(아직이면 타일이 "곧 찾아 드릴게요").
  final bool twinsReady;

  /// 쌍둥이 중 비울 수 있는 장(묶음마다 가장 최근 1장을 뺀 나머지).
  List<ScreenshotItem> get twinExtras => [for (final g in twins) ...g.skip(1)];

  /// 세 묶음 합(같은 캡처는 한 번만). 큰 타일 숫자.
  List<ScreenshotItem> get all {
    final seen = <int>{};
    return [
      for (final s in [...stale, ...etc, ...twinExtras])
        if (seen.add(s.id)) s,
    ];
  }

  bool get isEmpty => stale.isEmpty && etc.isEmpty && twins.isEmpty;
}

/// [items](최신순)에서 묶음을 고른다. [skip]의 asset id(휴지통·분석 제외)는 모든 묶음에서 뺀다.
TidyBundles computeBundles(
  List<ScreenshotItem> items,
  DateTime now, {
  Set<String> skip = const {},
  List<List<ScreenshotItem>> twins = const [],
  bool twinsReady = false,
}) {
  final kept = [
    for (final s in items)
      if (!skip.contains(s.localAssetId)) s,
  ];
  final staleBefore = now.subtract(const Duration(days: AppTidy.staleDays));
  return TidyBundles(
    stale: [
      for (final s in kept)
        if (s.takenAt.isBefore(staleBefore)) s,
    ],
    etc: [
      for (final s in kept)
        if (s.category == Category.etc) s,
    ],
    twins: [
      for (final g in twins)
        if (g.where((s) => !skip.contains(s.localAssetId)).length > 1)
          [
            for (final s in g)
              if (!skip.contains(s.localAssetId)) s,
          ],
    ],
    twinsReady: twinsReady,
  );
}

/// 가짜 데이터 모드(크롬)용 묶음. 가짜 캡처는 다 최근 것이라, 가장 오래된 3장을 "석 달째 안 봄"으로 보여 준다.
TidyBundles demoBundles(List<ScreenshotItem> items, DateTime now) {
  final real = computeBundles(items, now);
  final oldest = [...items]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  return TidyBundles(
    stale: oldest.take(3).toList().reversed.toList(),
    etc: real.etc,
    twins: real.twins,
    twinsReady: real.twinsReady,
  );
}

/// 이번 주 월요일 0시.
DateTime weekStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - (now.weekday - 1));

/// 이번 주(월~일) 요일별로 휴지통에 넣은 장수. `[0]`이 월요일.
List<int> weekCounts(Iterable<DateTime> trashedAt, DateTime now) {
  final start = weekStart(now);
  final counts = List.filled(7, 0);
  for (final at in trashedAt) {
    final day = DateTime(at.year, at.month, at.day).difference(start).inDays;
    if (day >= 0 && day < 7) counts[day]++;
  }
  return counts;
}

/// "약 1.2GB" / "약 350MB". 0이면 null(용량 줄을 숨긴다).
String? sizeLabel(int bytes) {
  if (bytes <= 0) return null;
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes < gb ~/ 10) return '약 ${(bytes / mb).ceil()}MB';
  final g = bytes / gb;
  return '약 ${g >= 10 ? g.round() : (g * 10).round() / 10}GB';
}
