import '../models/category.dart';
import '../models/category_summary.dart';
import '../models/category_update.dart';
import '../models/interest.dart';
import '../models/screenshot_item.dart';
import 'fake_data.dart';
import 'screenshot_repository.dart';

/// 메모리에 샘플을 들고 서버처럼 동작하는 가짜 저장소.
/// 목록 정렬(최신순)·필터·요약 집계·카테고리 수정 규칙은 서버(spec)와 같게 맞췄다.
class FakeScreenshotRepository implements ScreenshotRepository {
  /// [now]를 주입할 수 있게 해 두어 테스트에서 날짜가 고정된다.
  FakeScreenshotRepository({
    DateTime Function()? now,
    List<ScreenshotItem>? seed,
  }) : _now = now ?? DateTime.now,
       _items = List.of(seed ?? buildFakeScreenshots((now ?? DateTime.now)()));

  final DateTime Function() _now;
  final List<ScreenshotItem> _items;

  /// 앱 휴지통에 있는 캡처 id. 이 id들은 목록·요약·관심사에서 제외된다.
  final Set<int> _trashed = {};

  /// 테스트에서 휴지통 상태를 확인하기 위한 읽기 전용 보기.
  Set<int> get trashedIds => Set.unmodifiable(_trashed);

  static const _topTagCount = 3;
  static const _recentCount = 4;
  static const _interestMinCount = 3; // 서버 기본값(remine.interest.*)과 같게

  List<ScreenshotItem> get _sorted {
    final list = _items.where((s) => !_trashed.contains(s.id)).toList();
    list.sort((a, b) {
      final byTime = b.takenAt.compareTo(a.takenAt);
      return byTime != 0
          ? byTime
          : b.id.compareTo(a.id); // 서버: taken_at desc, id desc
    });
    return list;
  }

  @override
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) async {
    final filtered = _sorted
        .where((s) => category == null || s.category == category)
        .where((s) => tag == null || tag.isEmpty || s.tags.contains(tag))
        .toList();
    final from = (page * size).clamp(0, filtered.length);
    final to = (from + size).clamp(0, filtered.length);
    return ScreenshotPage(
      items: filtered.sublist(from, to),
      page: page,
      size: size,
      totalElements: filtered.length,
      totalPages: (filtered.length / size).ceil(),
    );
  }

  @override
  Future<List<ScreenshotItem>> all() async => _sorted;

  @override
  Future<CategorySummary> summary() async {
    final sorted = _sorted;
    return CategorySummary(
      categories: [
        for (final category in Category.values) _summaryOf(category, sorted),
      ],
    );
  }

  CategorySummaryItem _summaryOf(
    Category category,
    List<ScreenshotItem> sortedAll,
  ) {
    final inCategory = sortedAll.where((s) => s.category == category).toList();
    final tagCounts = <String, int>{};
    for (final s in inCategory) {
      for (final t in s.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    // 빈도 내림차순, 동점이면 이름순 (서버 요약과 같은 규칙)
    final topTags = tagCounts.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return CategorySummaryItem(
      category: category,
      count: inCategory.length,
      topTags: topTags.take(_topTagCount).map((e) => e.key).toList(),
      recentAssetIds: inCategory
          .take(_recentCount)
          .map((s) => s.localAssetId)
          .toList(),
    );
  }

  @override
  Future<CategoryUpdate> updateCategory(int id, Category category) async {
    final index = _items.indexWhere((s) => s.id == id);
    if (index < 0 || _trashed.contains(id)) {
      throw StateError('스크린샷을 찾을 수 없어요: $id'); // 서버는 404
    }
    // 같은 값이어도 USER가 된다(= 사용자 확인). autoCategory는 바뀌지 않는다. 태그는 그대로.
    final updated = _items[index].copyWith(
      category: category,
      categorySource: CategorySource.user,
    );
    _items[index] = updated;
    return CategoryUpdate(
      id: updated.id,
      category: updated.category,
      autoCategory: updated.autoCategory ?? updated.category,
      categorySource: CategorySource.user,
    );
  }

  @override
  Future<void> trash(int id) async {
    if (!_items.any((s) => s.id == id)) {
      throw StateError('스크린샷을 찾을 수 없어요: $id');
    }
    _trashed.add(id);
  }

  @override
  Future<void> restore(int id) async {
    _trashed.remove(id); // 정렬은 taken_at 기준이라 원래 자리로 자동 복귀
  }

  @override
  Future<List<Interest>> interests() async {
    final today = DateTime(_now().year, _now().month, _now().day);
    int daysSince(DateTime t) =>
        today.difference(DateTime(t.year, t.month, t.day)).inDays;

    // 서버와 같은 기준: 전체 기간, 최신순.
    final byTag = <String, List<ScreenshotItem>>{};
    for (final s in _sorted) {
      for (final t in s.tags) {
        byTag.putIfAbsent(t, () => []).add(s);
      }
    }
    final repeated = byTag.entries
        .where((e) => e.value.length >= _interestMinCount)
        .toList();
    final interestTags = {for (final e in repeated) e.key};
    // 서버와 같은 기준: 같은 캡처에 함께 붙은 다른 관심사 태그.
    List<String> linked(String tag) => [
      for (final other in interestTags)
        if (other != tag && byTag[tag]!.any((s) => s.tags.contains(other)))
          other,
    ];
    // 가장 많은 달(같으면 최근 달 — 최신순이라 먼저 센 달이 이긴다).
    (int, int) peak(List<ScreenshotItem> shots) {
      final byMonth = <(int, int), int>{};
      for (final s in shots) {
        byMonth.update(
          (s.takenAt.year, s.takenAt.month),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final best = byMonth.entries.reduce((a, b) => b.value > a.value ? b : a);
      return (best.key.$2, best.value);
    }

    return sortInterests([
      for (final e in repeated)
        Interest(
          tag: e.key,
          category: e.value.first.category,
          forgotten:
              daysSince(e.value.first.takenAt) > Interest.defaultRecentDays,
          captureCount: e.value.length,
          dormantDays: daysSince(e.value.first.takenAt),
          peakMonth: peak(e.value).$1,
          peakMonthCount: peak(e.value).$2,
          latestMonth: e.value.first.takenAt.month,
          latestMonthCount: e.value
              .where(
                (s) =>
                    s.takenAt.year == e.value.first.takenAt.year &&
                    s.takenAt.month == e.value.first.takenAt.month,
              )
              .length,
          recent: [
            for (final s in e.value.take(3))
              InterestCapture(
                id: s.id,
                localAssetId: s.localAssetId,
                takenAt: s.takenAt,
              ),
          ],
          linkedTags: linked(e.key),
        ),
    ]);
  }
}
