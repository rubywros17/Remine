import 'dart:async';
import 'dart:convert';

import '../../models/category.dart';
import '../../models/category_summary.dart';
import '../../models/category_update.dart';
import '../../models/interest.dart';
import '../../models/screenshot_item.dart';
import '../device/trash_store.dart';
import '../screenshot_repository.dart';
import 'api_client.dart';
import 'remote_state_store.dart';
import 'sync_status.dart';

/// 서버 API로 목록·요약을 읽고 카테고리를 고치는 [ScreenshotRepository].
///
/// - 응답을 받을 때마다 **마지막 목록·요약을 로컬 DB에 저장**한다. 서버에 닿지 못하면 저장해 둔 것을 보여 주고
///   [SyncStatus]에 연결 문제를 알려 홈이 배너를 띄운다. 저장한 게 없으면 빈 결과다(앱이 죽지 않는다).
/// - 목록 항목을 받을 때 asset id ↔ 서버 id 매핑도 채운다.
/// - 휴지통은 [TrashStore]에 남긴다. 스와이프는 서버 응답을 기다리지 않고, 목록·요약은 여기서 직접 뺀다.
///   서버에는 [onTrashChanged]로 알리고(관심사 집계에서 빼려고), 실패하면 대기열에 남아 다음 동기화 때 다시 보낸다.
/// - 기기에서 분류한 캡처는 이 클래스가 아니라 [LocalMergedRepository]가 합친다.
class RemoteRepository implements ScreenshotRepository {
  RemoteRepository(this._api, this._state, this._status, {TrashStore? trash})
    : _trash = trash ?? InMemoryTrashStore();

  final RemineApi _api;
  final RemoteStateStore _state;
  final SyncStatus _status;

  final TrashStore _trash;
  final Map<int, ScreenshotItem> _seen = {};

  /// 휴지통이 바뀌면 부른다(SyncService가 서버에 알린다).
  Future<void> Function()? onTrashChanged;

  Future<List<TrashedShot>> _serverTrash() async => [
    for (final t in await _trash.hidden())
      if (t.onServer) t,
  ];

  static ScreenshotPage _empty(int page, int size) => ScreenshotPage(
    items: const [],
    page: page,
    size: size,
    totalElements: 0,
    totalPages: 0,
  );

  @override
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  }) async {
    final key = 'list|${category?.code ?? ''}|${tag ?? ''}|$page|$size';
    final json = await _fetch(
      key,
      (deviceId) => _api.listJson(
        deviceId,
        category: category,
        tag: tag,
        page: page,
        size: size,
      ),
    );
    if (json == null) return _empty(page, size);
    try {
      final parsed = ScreenshotPage.fromJson(json);
      for (final item in parsed.items) {
        _seen[item.id] = item;
      }
      await _state.linkServerIds({
        for (final item in parsed.items) item.localAssetId: item.id,
      });
      final trashed = {for (final t in await _serverTrash()) t.assetId};
      final items = parsed.items
          .where((s) => !trashed.contains(s.localAssetId))
          .toList();
      return ScreenshotPage(
        items: items,
        page: parsed.page,
        size: parsed.size,
        totalElements:
            parsed.totalElements - (parsed.items.length - items.length),
        totalPages: parsed.totalPages,
      );
    } catch (_) {
      return _empty(page, size); // 깨진 응답·캐시. 내용은 남기지 않는다.
    }
  }

  @override
  Future<CategorySummary> summary() async {
    final json = await _fetch('summary', _api.summaryJson);
    try {
      final parsed = json == null ? null : CategorySummary.fromJson(json);
      if (parsed != null) return _withoutTrashed(parsed, await _serverTrash());
    } catch (_) {}
    return CategorySummary(
      categories: [
        for (final c in Category.values)
          CategorySummaryItem(
            category: c,
            count: 0,
            topTags: const [],
            recentAssetIds: const [],
          ),
      ],
    );
  }

  CategorySummary _withoutTrashed(
    CategorySummary s,
    List<TrashedShot> trashed,
  ) {
    if (trashed.isEmpty) return s;
    final ids = {for (final t in trashed) t.assetId};
    return CategorySummary(
      categories: [
        for (final c in s.categories)
          CategorySummaryItem(
            category: c.category,
            count:
                (c.count -
                        trashed.where((t) => t.category == c.category).length)
                    .clamp(0, c.count),
            topTags: c.topTags,
            recentAssetIds: [
              for (final id in c.recentAssetIds)
                if (!ids.contains(id)) id,
            ],
          ),
      ],
    );
  }

  /// 서버에서 받아 캐시에 저장하고 JSON을 돌려준다. 실패하면 캐시(없으면 null)를 돌려주고 [SyncStatus]에 알린다.
  Future<Map<String, dynamic>?> _fetch(
    String key,
    Future<Map<String, dynamic>> Function(int deviceId) call,
  ) async {
    final deviceId = await _state.deviceId();
    if (deviceId != null) {
      try {
        final json = await call(deviceId);
        await _state.putCache(key, jsonEncode(json));
        _status.reportFetch(null);
        return json;
      } on ApiException catch (e) {
        _status.reportFetch(e.failure);
      }
    }
    final cached = await _state.cached(key);
    if (cached == null) return null;
    try {
      return jsonDecode(cached) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CategoryUpdate> updateCategory(int id, Category category) async {
    final deviceId = await _state.deviceId();
    if (deviceId == null) throw const ApiException(ApiFailure.offline);
    try {
      final result = await _api.updateCategory(deviceId, id, category);
      _status.reportFetch(null);
      return result;
    } on ApiException catch (e) {
      _status.reportFetch(e.failure);
      rethrow;
    }
  }

  @override
  Future<void> trash(int id) async {
    final item = _seen[id];
    if (item == null) return;
    await _trash.add(
      TrashedShot(
        assetId: item.localAssetId,
        category: item.category,
        takenAt: item.takenAt,
        trashedAt: DateTime.now(),
        onServer: true,
      ),
    );
    _notifyTrash();
  }

  @override
  Future<void> restore(int id) async {
    final item = _seen[id];
    if (item == null) return;
    await _trash.restore(item.localAssetId);
    _notifyTrash();
  }

  // 기다리지 않는다: 스와이프 모션이 서버 응답에 묶이지 않게. 실패해도 대기열에 남는다.
  void _notifyTrash() => unawaited(onTrashChanged?.call());

  /// 서버 기준값(응답의 `minCount`)이 없을 때(옛 응답·캐시) 쓰는 값. 서버 기본값과 같다.
  static const fallbackMinCount = 3;

  /// GET /api/interests. 서버가 휴지통 캡처를 빼고 세지만, 아직 서버에 못 알린 캡처가 있을 수 있어 여기서도 뺀다.
  /// 그래서 기준 횟수 아래로 내려간 관심사는 숨긴다(응답의 `recent`에 있는 캡처만 알 수 있는 한계는 알리기 전까지만이다).
  @override
  Future<List<Interest>> interests() async {
    final json = await _fetch('interests', _api.interestsJson);
    if (json == null) return const [];
    try {
      final minCount = (json['minCount'] as num?)?.toInt() ?? fallbackMinCount;
      final spanDays = (json['windowDays'] as num).toInt();
      final trashed = {for (final t in await _serverTrash()) t.assetId};
      Interest withoutTrashed(Interest i) => i.without({
        for (final c in i.recent)
          if (trashed.contains(c.localAssetId)) c.id,
      });
      return [
        for (final item in json['items'] as List)
          withoutTrashed(
            Interest.fromJson(item as Map<String, dynamic>, spanDays: spanDays),
          ),
      ].where((i) => i.captureCount >= minCount).toList();
    } catch (_) {
      return const []; // 깨진 응답·캐시. 내용은 남기지 않는다.
    }
  }
}
