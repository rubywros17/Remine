import '../../../models/category.dart';
import '../local_db.dart';
import 'privacy_filter.dart';

/// 기기 안 판정 결과 한 건. **사유 코드만** 들어 있고 감지된 값·OCR 원문은 없다.
class StoredVerdict {
  const StoredVerdict({
    this.localId = 0,
    required this.assetId,
    required this.takenAt,
    required this.modifiedAt,
    required this.route,
    this.category,
    this.hidden = false,
    this.reasons = const [],
    required this.decidedAt,
  });

  /// 저장소가 붙이는 번호(저장 전에는 0). 홈 목록에서는 서버 id와 겹치지 않게 `-localId`를 id로 쓴다.
  final int localId;
  final String assetId;
  final DateTime takenAt;

  /// 사진이 바뀌었는지 보는 값(epoch 초). 같으면 다시 판정하지 않는다.
  final int modifiedAt;
  final LocalRoute route;
  final Category? category;
  final bool hidden;
  final List<String> reasons;
  final DateTime decidedAt;

  factory StoredVerdict.of(
    LocalVerdict v, {
    required String assetId,
    required DateTime takenAt,
    required int modifiedAt,
    required DateTime now,
  }) => StoredVerdict(
    assetId: assetId,
    takenAt: takenAt,
    modifiedAt: modifiedAt,
    route: v.route,
    category: v.category,
    hidden: v.hidden,
    reasons: v.reasons,
    decidedAt: now,
  );
}

abstract interface class LocalVerdictStore {
  Future<StoredVerdict?> find(String assetId);

  /// assetId가 같으면 덮어쓴다(localId는 유지).
  Future<void> save(StoredVerdict verdict);

  /// 기기에서 분류가 끝난([LocalRoute.deviceOnly]) 건. [hidden]이 null이면 숨김 여부와 상관없이 전부.
  Future<List<StoredVerdict>> deviceOnly({bool? hidden});

  /// 갤러리에서 지운 캡처의 판정을 지운다.
  Future<void> removeAll(Iterable<String> assetIds);

  Future<void> clear();
}

StoredVerdict storedVerdictFromRow(Map<String, Object?> r) {
  final category = r['category'] as String?;
  final reasons = r['reasons'] as String;
  return StoredVerdict(
    localId: r['local_id'] as int,
    assetId: r['asset_id'] as String,
    takenAt: DateTime.fromMillisecondsSinceEpoch(r['taken_at'] as int),
    modifiedAt: r['modified_at'] as int,
    route: LocalRoute.values.byName(r['route'] as String),
    category: category == null ? null : Category.fromJson(category),
    hidden: (r['hidden'] as int) == 1,
    reasons: reasons.isEmpty ? const [] : reasons.split(','),
    decidedAt: DateTime.fromMillisecondsSinceEpoch(r['decided_at'] as int),
  );
}

Map<String, Object?> storedVerdictToRow(StoredVerdict v) => {
  'asset_id': v.assetId,
  'taken_at': v.takenAt.millisecondsSinceEpoch,
  'modified_at': v.modifiedAt,
  'route': v.route.name,
  'category': v.category?.code,
  'hidden': v.hidden ? 1 : 0,
  'reasons': v.reasons.join(','),
  'decided_at': v.decidedAt.millisecondsSinceEpoch,
};

class SqfliteLocalVerdictStore implements LocalVerdictStore {
  SqfliteLocalVerdictStore(this._local);

  final LocalDb _local;

  @override
  Future<StoredVerdict?> find(String assetId) async {
    final rows = await (await _local.db).query(
      'local_verdict',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
    return rows.isEmpty ? null : storedVerdictFromRow(rows.first);
  }

  @override
  Future<void> save(StoredVerdict v) async {
    final db = await _local.db;
    final updated = await db.update(
      'local_verdict',
      storedVerdictToRow(v),
      where: 'asset_id = ?',
      whereArgs: [v.assetId],
    );
    if (updated == 0) await db.insert('local_verdict', storedVerdictToRow(v));
  }

  @override
  Future<List<StoredVerdict>> deviceOnly({bool? hidden}) async {
    final rows = await (await _local.db).query(
      'local_verdict',
      where: hidden == null
          ? 'route = ?'
          : 'route = ? AND hidden = ${hidden ? 1 : 0}',
      whereArgs: [LocalRoute.deviceOnly.name],
      orderBy: 'taken_at DESC, local_id DESC',
    );
    return rows.map(storedVerdictFromRow).toList();
  }

  @override
  Future<void> removeAll(Iterable<String> assetIds) async {
    final db = await _local.db;
    for (final id in assetIds) {
      await db.delete('local_verdict', where: 'asset_id = ?', whereArgs: [id]);
    }
  }

  @override
  Future<void> clear() async => (await _local.db).delete('local_verdict');
}

/// 테스트·크롬용 메모리 저장소.
class InMemoryLocalVerdictStore implements LocalVerdictStore {
  final Map<String, StoredVerdict> _rows = {};
  int _nextId = 1;

  /// 테스트에서 저장된 내용을 통째로 검사하려는 읽기용 보기.
  List<StoredVerdict> get all => _rows.values.toList();

  @override
  Future<StoredVerdict?> find(String assetId) async => _rows[assetId];

  @override
  Future<void> save(StoredVerdict v) async {
    final id = _rows[v.assetId]?.localId ?? _nextId++;
    _rows[v.assetId] = StoredVerdict(
      localId: id,
      assetId: v.assetId,
      takenAt: v.takenAt,
      modifiedAt: v.modifiedAt,
      route: v.route,
      category: v.category,
      hidden: v.hidden,
      reasons: v.reasons,
      decidedAt: v.decidedAt,
    );
  }

  @override
  Future<List<StoredVerdict>> deviceOnly({bool? hidden}) async {
    final list = _rows.values
        .where(
          (v) =>
              v.route == LocalRoute.deviceOnly &&
              (hidden == null || v.hidden == hidden),
        )
        .toList();
    list.sort((a, b) {
      final byTime = b.takenAt.compareTo(a.takenAt);
      return byTime != 0 ? byTime : b.localId.compareTo(a.localId);
    });
    return list;
  }

  @override
  Future<void> removeAll(Iterable<String> assetIds) async =>
      assetIds.forEach(_rows.remove);

  @override
  Future<void> clear() async => _rows.clear();
}
