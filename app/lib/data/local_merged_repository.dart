import '../models/category.dart';
import '../models/category_summary.dart';
import '../models/category_update.dart';
import '../models/interest.dart';
import '../models/screenshot_item.dart';
import 'device/privacy/app_rules.dart';
import 'device/privacy/local_verdict_store.dart';
import 'device/trash_store.dart';
import 'screenshot_repository.dart';

/// 기본 저장소([base], 서버 분석 결과)에 **기기 안에서 분류한 캡처**를 합쳐 보여 주는 저장소.
///
/// - 합치는 건 숨김이 아닌 것뿐이다(메신저 앱 → `CHAT`). 숨김(민감 정보·금융 앱)은 개수·목록에서 빠지고
///   "분석 제외" 화면에서만 보인다.
/// - 서버 id와 겹치지 않게 기기 판정 캡처의 id는 음수(`-localId`)다.
/// - 한계: 기기 판정 캡처의 카테고리 수정은 아직 안 된다(서버 연동 브랜치에서 로컬 저장을 붙인다).
/// - 휴지통은 [TrashStore]에 남는다. 기기 판정 캡처는 서버에 없으니 어떤 요청도 보내지 않는다.
/// - 출처(`sourceApp`)는 서버로 보내지 않으므로 서버 응답엔 없다. 목록을 돌려줄 때 [fileNameOf]로 찾은
///   갤럭시 파일명의 앱 이름(대문자)을 기기에서 채운다.
class LocalMergedRepository implements ScreenshotRepository {
  LocalMergedRepository(
    this._base,
    this._verdicts, {
    TrashStore? trash,
    this.fileNameOf,
  }) : _trash = trash ?? InMemoryTrashStore();

  final ScreenshotRepository _base;
  final LocalVerdictStore _verdicts;
  final TrashStore _trash;

  /// asset id → 파일명. 없으면 출처를 채우지 않는다.
  final Future<String?> Function(String assetId)? fileNameOf;

  /// asset id → 앱 이름(없으면 null). 한 번 찾은 건 다시 찾지 않는다(파일명은 바뀌지 않는다).
  final _sourceApps = <String, String?>{};

  Future<List<ScreenshotItem>> _withSourceApp(
    List<ScreenshotItem> items,
  ) async {
    final lookup = fileNameOf;
    if (lookup == null) return items;
    final missing = {
      for (final s in items)
        if (!_sourceApps.containsKey(s.localAssetId)) s.localAssetId,
    };
    final names = await Future.wait(missing.map(lookup));
    var i = 0;
    for (final id in missing) {
      _sourceApps[id] = appNameFromFileName(names[i++] ?? '')?.toUpperCase();
    }
    return [
      for (final s in items)
        s.sourceApp != null
            ? s
            : s.copyWith(sourceApp: _sourceApps[s.localAssetId]),
    ];
  }

  static const _recentCount = 4;

  Future<List<ScreenshotItem>> _localItems(Category? category) async {
    final rows = await _verdicts.deviceOnly(hidden: false);
    final trashed = {for (final t in await _trash.all()) t.assetId};
    return [
      for (final v in rows)
        if (v.category != null &&
            (category == null || v.category == category) &&
            !trashed.contains(v.assetId))
          ScreenshotItem(
            id: -v.localId,
            localAssetId: v.assetId,
            takenAt: v.takenAt,
            category: v.category!,
            tags: const [],
            autoCategory: v.category,
            categorySource: CategorySource.auto,
          ),
    ];
  }

  static int _newestFirst(ScreenshotItem a, ScreenshotItem b) {
    final byTime = b.takenAt.compareTo(a.takenAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  @override
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) async {
    final p = await _merged(
      category: category,
      tag: tag,
      page: page,
      size: size,
    );
    return ScreenshotPage(
      items: await _withSourceApp(p.items),
      page: p.page,
      size: p.size,
      totalElements: p.totalElements,
      totalPages: p.totalPages,
    );
  }

  Future<ScreenshotPage> _merged({
    required Category? category,
    required String? tag,
    required int page,
    required int size,
  }) async {
    final hasTag = tag != null && tag.isNotEmpty;
    // 기기 판정 캡처에는 태그가 없다 → 태그로 거르면 서버 결과만 남는다.
    final local = hasTag ? <ScreenshotItem>[] : await _localItems(category);
    if (local.isEmpty) {
      return _base.list(category: category, tag: tag, page: page, size: size);
    }
    // 두 목록을 최신순으로 합친 앞쪽 (page+1)*size개는 각 목록의 앞쪽 (page+1)*size개 안에 있다.
    final upTo = (page + 1) * size;
    final base = await _base.list(category: category, tag: tag, size: upTo);
    final merged = [...base.items, ...local]..sort(_newestFirst);
    final from = (page * size).clamp(0, merged.length);
    final to = upTo.clamp(0, merged.length);
    final total = base.totalElements + local.length;
    return ScreenshotPage(
      items: merged.sublist(from, to),
      page: page,
      size: size,
      totalElements: total,
      totalPages: (total / size).ceil(),
    );
  }

  @override
  Future<CategorySummary> summary() async {
    final base = await _base.summary();
    final local = await _localItems(null);
    if (local.isEmpty) return base;
    final items = <CategorySummaryItem>[];
    for (final item in base.categories) {
      final mine = local.where((s) => s.category == item.category).toList()
        ..sort(_newestFirst);
      if (mine.isEmpty) {
        items.add(item);
        continue;
      }
      final top = await _base.list(category: item.category, size: _recentCount);
      final recent = [...top.items, ...mine.take(_recentCount)]
        ..sort(_newestFirst);
      items.add(
        CategorySummaryItem(
          category: item.category,
          count: item.count + mine.length,
          topTags: item.topTags,
          recentAssetIds: [
            for (final s in recent.take(_recentCount)) s.localAssetId,
          ],
        ),
      );
    }
    return CategorySummary(categories: items);
  }

  @override
  Future<CategoryUpdate> updateCategory(int id, Category category) {
    if (id < 0) {
      throw StateError('기기에서 분류한 캡처는 아직 카테고리를 바꿀 수 없어요: $id');
    }
    return _base.updateCategory(id, category);
  }

  Future<StoredVerdict?> _verdictOf(int id) async {
    for (final v in await _verdicts.deviceOnly(hidden: false)) {
      if (v.localId == -id) return v;
    }
    return null;
  }

  @override
  Future<void> trash(int id) async {
    if (id >= 0) return _base.trash(id);
    final v = await _verdictOf(id);
    final category = v?.category;
    if (v == null || category == null) return;
    await _trash.add(
      TrashedShot(
        assetId: v.assetId,
        category: category,
        takenAt: v.takenAt,
        trashedAt: DateTime.now(),
        onServer: false,
      ),
    );
  }

  @override
  Future<void> restore(int id) async {
    if (id >= 0) return _base.restore(id);
    final v = await _verdictOf(id);
    if (v != null) await _trash.restore(v.assetId);
  }

  @override
  Future<List<Interest>> interests() => _base.interests();
}
