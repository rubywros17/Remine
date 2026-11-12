import '../core/tokens.dart';
import 'device/trash_store.dart';
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

/// 가짜 데이터 모드(크롬)용 묶음. 가짜 캡처는 다 최근 것이고 OCR 원문도 없어서,
/// 가장 오래된 3장을 "석 달째 안 봄"으로, 같은 출처 앱 2장씩 두 묶음을 쌍둥이로 보여 준다.
TidyBundles demoBundles(List<ScreenshotItem> items, DateTime now) {
  final real = computeBundles(items, now);
  final oldest = [...items]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  final byApp = <String, List<ScreenshotItem>>{};
  for (final s in items) {
    if (s.sourceApp != null) byApp.putIfAbsent(s.sourceApp!, () => []).add(s);
  }
  return TidyBundles(
    stale: oldest.take(3).toList().reversed.toList(),
    etc: real.etc,
    twins: [
      for (final g in byApp.values.where((g) => g.length > 1).take(2))
        g.take(2).toList(),
    ],
    twinsReady: true,
  );
}

// ── 쌍둥이 캡처 ──

/// 쌍둥이 비교에 넘기는 한 장. OCR 원문은 기기 안(isolate)에서 비교만 하고 버린다.
class TwinInput {
  const TwinInput(this.assetId, this.app, this.takenAt, this.text);

  final String assetId;
  final String app;
  final DateTime takenAt;
  final String text;
}

/// 쌍둥이 후보: 같은 출처 앱 캡처가 [AppTidy.twinWindow] 안에 하나라도 더 있는 것.
/// OCR 원문은 이 후보만 읽는다(메인 isolate에서 DB를 묻는 횟수를 줄인다).
List<ScreenshotItem> twinCandidates(List<ScreenshotItem> items) {
  final byApp = <String, List<ScreenshotItem>>{};
  for (final s in items) {
    final app = s.sourceApp;
    if (app != null) byApp.putIfAbsent(app, () => []).add(s);
  }
  final out = <ScreenshotItem>[];
  for (final g in byApp.values) {
    g.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    for (var i = 0; i < g.length; i++) {
      bool near(int j) =>
          j >= 0 &&
          j < g.length &&
          g[j].takenAt.difference(g[i].takenAt).abs() <= AppTidy.twinWindow;
      if (near(i - 1) || near(i + 1)) out.add(g[i]);
    }
  }
  return out;
}

/// 쌍둥이 묶음(asset id, 묶음마다 최신순 · 묶음끼리도 최신순).
/// 같은 앱 + [AppTidy.twinWindow] 안 + 글자 바이그램 Jaccard ≥ [AppTidy.twinSimilarity]. 글자가 2자 미만이면 뺀다.
/// 시간순으로 정렬한 뒤 창 안의 쌍만 비교한다(전체 n² 비교를 하지 않는다).
///
/// [Flutter 메모] `compute(findTwins, inputs)`로 다른 isolate(별도 스레드)에서 돌린다. isolate에서는 DB·플러그인을
/// 부를 수 없어서, 원문은 메인에서 읽어 [TwinInput]으로 넘기고 여기서는 비교만 한다.
List<List<String>> findTwins(List<TwinInput> inputs) {
  final xs = [
    for (final x in inputs)
      if (x.text.replaceAll(RegExp(r'\s'), '').runes.length >= 2) x,
  ]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  final grams = [for (final x in xs) _bigrams(x.text)];
  final parent = List.generate(xs.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      i = parent[i] = parent[parent[i]];
    }
    return i;
  }

  for (var i = 0; i < xs.length; i++) {
    for (var j = i + 1; j < xs.length; j++) {
      if (xs[j].takenAt.difference(xs[i].takenAt) > AppTidy.twinWindow) break;
      if (xs[j].app != xs[i].app) continue;
      if (jaccard(grams[i], grams[j]) >= AppTidy.twinSimilarity) {
        parent[root(j)] = root(i);
      }
    }
  }
  final groups = <int, List<TwinInput>>{};
  for (var i = 0; i < xs.length; i++) {
    groups.putIfAbsent(root(i), () => []).add(xs[i]);
  }
  final out = [
    for (final g in groups.values)
      if (g.length > 1) (g..sort((a, b) => b.takenAt.compareTo(a.takenAt))),
  ]..sort((a, b) => b.first.takenAt.compareTo(a.first.takenAt));
  return [
    for (final g in out) [for (final x in g) x.assetId],
  ];
}

/// 공백을 뺀 글자 2개씩 묶음(바이그램) 집합.
Set<String> _bigrams(String text) {
  final s = text.replaceAll(RegExp(r'\s'), '').runes.toList();
  return {
    for (var i = 0; i + 1 < s.length; i++)
      String.fromCharCodes([s[i], s[i + 1]]),
  };
}

/// 두 집합의 Jaccard 유사도(교집합 / 합집합).
double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final inter = a.where(b.contains).length;
  return inter / (a.length + b.length - inter);
}

/// 글자 바이그램 Jaccard(테스트·디버그용).
double textSimilarity(String a, String b) => jaccard(_bigrams(a), _bigrams(b));

/// 이번 주 월요일 0시.
DateTime weekStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - (now.weekday - 1));

/// 정리 탭 "이번 주 비운 스크린샷"(디자인 캔버스 D3 점선 도장).
class TidyWeek {
  const TidyWeek({
    required this.counts,
    required this.bytes,
    required this.remaining,
    required this.todayIndex,
    this.sizedCount = 0,
    this.estimatedBytes,
  });

  /// 요일별(월~일) 휴지통에 넣은 장수. 되살린 건 빠져 있다.
  final List<int> counts;

  /// 크기를 아는 기록만 더한 값. 하나도 모르면 null.
  final int? bytes;

  /// 크기를 아는 장수.
  final int sizedCount;

  /// 모르는 장까지 평균으로 추정해 더한 값([weekOf]). 추정할 평균이 없으면 null(용량 대신 장수를 크게).
  final int? estimatedBytes;

  /// 지금 남은 장수(정리 탭이 쓰는 목록 기준: 휴지통·숨김 제외).
  final int remaining;

  /// 오늘 요일 칸(0 = 월).
  final int todayIndex;

  int get cleared => counts.fold(0, (a, b) => a + b);

  /// 이번 주 비운 장의 크기를 전부 안다(추정 없음).
  bool get sizeComplete => cleared > 0 && sizedCount == cleared;
}

/// 이번 주(월요일 시작) 휴지통 기록으로 [TidyWeek]를 만든다.
///
/// 크기를 모르는 장(크기 기록 전·영구 삭제)은 추정한다: 아는 장이 있으면 그 평균, 하나도 없으면
/// [listAverage](정리 탭 목록 스크린샷의 평균 크기). 둘 다 없으면 [TidyWeek.estimatedBytes]는 null.
TidyWeek weekOf(
  Iterable<TrashLogEntry> log,
  DateTime now,
  int remaining, {
  double? listAverage,
}) {
  final start = weekStart(now);
  final counts = List.filled(7, 0);
  int? bytes;
  var sized = 0;
  for (final e in log) {
    final at = e.trashedAt;
    final day = DateTime(at.year, at.month, at.day).difference(start).inDays;
    if (day < 0 || day >= 7) continue;
    counts[day]++;
    final size = e.size;
    if (size != null) {
      bytes = (bytes ?? 0) + size;
      sized++;
    }
  }
  final cleared = counts.fold(0, (a, b) => a + b);
  final unknown = cleared - sized;
  final average = sized > 0 ? bytes! / sized : listAverage;
  final int? estimated = unknown == 0
      ? bytes
      : average == null
      ? null
      : ((bytes ?? 0) + average * unknown).round();
  return TidyWeek(
    counts: counts,
    bytes: bytes,
    sizedCount: sized,
    estimatedBytes: estimated,
    remaining: remaining,
    todayIndex: now.weekday - 1,
  );
}

/// "18MB" / "1.2GB" / "0.1MB": 1000MB 미만은 MB, 이상은 GB. 소수 한 자리(.0은 뺀다), 아무리 작아도 0.1MB.
String freedLabel(int bytes) {
  const mb = 1024 * 1024;
  String oneDecimal(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }

  final m = bytes / mb;
  if (m >= 1000) return '${oneDecimal(m / 1024)}GB';
  return '${oneDecimal(m < 0.1 ? 0.1 : m)}MB';
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
