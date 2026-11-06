import '../../models/category.dart';
import 'local_db.dart';

/// 앱 휴지통의 한 장. asset id가 키다(서버 id는 기기 재등록 때 바뀐다).
class TrashedShot {
  const TrashedShot({
    required this.assetId,
    required this.category,
    required this.takenAt,
    required this.trashedAt,
    required this.onServer,
  });

  final String assetId;
  final Category category;
  final DateTime takenAt;
  final DateTime trashedAt;

  /// 서버에 있는 캡처인지. 기기에서만 분류한 캡처는 false이고, 서버에 어떤 요청도 보내지 않는다(asset id도).
  final bool onServer;
}

/// 서버에 아직 알리지 못한 일. 네트워크가 안 되면 여기 남고 다음 동기화 때 다시 보낸다.
class TrashOutbox {
  const TrashOutbox({
    this.trash = const [],
    this.restore = const [],
    this.forget = const [],
  });

  final List<String> trash;
  final List<String> restore;
  final List<String> forget;

  bool get isEmpty => trash.isEmpty && restore.isEmpty && forget.isEmpty;
}

/// 앱 휴지통과 서버 반영 대기열. 앱을 다시 켜도 남는다.
abstract interface class TrashStore {
  /// 휴지통에 넣는다. 서버 캡처면 서버 반영 대기로 표시한다.
  Future<void> add(TrashedShot shot);

  /// 되살린다. 서버 캡처면 서버에 알릴 때까지 대기열에 남고, 목록에서는 바로 빠진다.
  Future<void> restore(String assetId);

  /// 갤러리에서 지웠다. 서버 캡처면 서버에서 지울 때까지 대기열에 남고, 목록에서는 바로 빠진다.
  Future<void> markDeleted(Iterable<String> assetIds);

  /// 휴지통에 있는 캡처, 버린 시각 최신순.
  Future<List<TrashedShot>> all();

  /// 목록·요약에서 뺄 캡처: 휴지통에 있거나, 갤러리에서 지웠는데 서버에서 아직 못 지운 것.
  Future<List<TrashedShot>> hidden();

  Future<TrashOutbox> outbox();

  /// 서버에 알린 뒤 대기를 지운다.
  Future<void> trashSent(Iterable<String> assetIds);
  Future<void> restoreSent(Iterable<String> assetIds);
  Future<void> forgetSent(Iterable<String> assetIds);

  /// 기기를 재등록하면 서버 쪽 표시가 사라진다. 휴지통에 있는 서버 캡처를 다시 대기로 돌린다.
  Future<void> resendAll();
}

const _trashed = 'TRASHED'; // 휴지통에 있음. pending이면 서버에 아직 안 알림
const _restoring = 'RESTORING'; // 되살렸고 서버에 알리는 중
const _forgetting = 'FORGETTING'; // 갤러리에서 지웠고 서버에서 지우는 중

class SqfliteTrashStore implements TrashStore {
  SqfliteTrashStore(this._local);

  final LocalDb _local;

  @override
  Future<void> add(TrashedShot shot) async {
    final db = await _local.db;
    await db.rawInsert(
      'INSERT OR REPLACE INTO trash '
      '(asset_id, category, taken_at, trashed_at, on_server, state, pending) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        shot.assetId,
        shot.category.code,
        shot.takenAt.millisecondsSinceEpoch,
        shot.trashedAt.millisecondsSinceEpoch,
        shot.onServer ? 1 : 0,
        _trashed,
        shot.onServer ? 1 : 0,
      ],
    );
  }

  @override
  Future<void> restore(String assetId) => _leave([assetId], _restoring);

  @override
  Future<void> markDeleted(Iterable<String> assetIds) =>
      _leave(assetIds, _forgetting);

  /// 휴지통에서 내보낸다. 기기 전용은 바로 지우고, 서버 캡처는 알릴 때까지 [state]로 남긴다.
  Future<void> _leave(Iterable<String> assetIds, String state) async {
    final db = await _local.db;
    await db.transaction((tx) async {
      for (final id in assetIds) {
        await tx.delete(
          'trash',
          where: 'asset_id = ? AND on_server = 0',
          whereArgs: [id],
        );
        await tx.update(
          'trash',
          {'state': state, 'pending': 1},
          where: 'asset_id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<List<TrashedShot>> all() => _query('state = ?', [_trashed]);

  @override
  Future<List<TrashedShot>> hidden() => _query('state != ?', [_restoring]);

  Future<List<TrashedShot>> _query(String where, List<Object> args) async {
    final db = await _local.db;
    final rows = await db.query(
      'trash',
      where: where,
      whereArgs: args,
      orderBy: 'trashed_at DESC, asset_id',
    );
    return [
      for (final r in rows)
        TrashedShot(
          assetId: r['asset_id'] as String,
          category: Category.fromJson(r['category'] as String),
          takenAt: DateTime.fromMillisecondsSinceEpoch(r['taken_at'] as int),
          trashedAt: DateTime.fromMillisecondsSinceEpoch(
            r['trashed_at'] as int,
          ),
          onServer: r['on_server'] == 1,
        ),
    ];
  }

  @override
  Future<TrashOutbox> outbox() async {
    final db = await _local.db;
    final rows = await db.query(
      'trash',
      columns: ['asset_id', 'state'],
      where: 'pending = 1',
    );
    List<String> of(String state) => [
      for (final r in rows)
        if (r['state'] == state) r['asset_id'] as String,
    ];
    return TrashOutbox(
      trash: of(_trashed),
      restore: of(_restoring),
      forget: of(_forgetting),
    );
  }

  // 보내는 사이 상태가 바뀌었으면(되돌리기 등) 그 대기는 지우지 않는다.
  @override
  Future<void> trashSent(Iterable<String> assetIds) async {
    final db = await _local.db;
    for (final id in assetIds) {
      await db.update(
        'trash',
        {'pending': 0},
        where: 'asset_id = ? AND state = ?',
        whereArgs: [id, _trashed],
      );
    }
  }

  @override
  Future<void> restoreSent(Iterable<String> assetIds) =>
      _deleteIn(assetIds, _restoring);

  @override
  Future<void> forgetSent(Iterable<String> assetIds) =>
      _deleteIn(assetIds, _forgetting);

  Future<void> _deleteIn(Iterable<String> assetIds, String state) async {
    final db = await _local.db;
    for (final id in assetIds) {
      await db.delete(
        'trash',
        where: 'asset_id = ? AND state = ?',
        whereArgs: [id, state],
      );
    }
  }

  @override
  Future<void> resendAll() async {
    final db = await _local.db;
    await db.update(
      'trash',
      {'pending': 1},
      where: 'on_server = 1 AND state = ?',
      whereArgs: [_trashed],
    );
  }
}

/// 메모리 구현(가짜 데이터·테스트). 앱을 다시 켜면 사라진다.
class InMemoryTrashStore implements TrashStore {
  final Map<String, _Row> _rows = {};

  @override
  Future<void> add(TrashedShot shot) async =>
      _rows[shot.assetId] = _Row(shot, _trashed, shot.onServer);

  @override
  Future<void> restore(String assetId) async => _leave([assetId], _restoring);

  @override
  Future<void> markDeleted(Iterable<String> assetIds) async =>
      _leave(assetIds, _forgetting);

  void _leave(Iterable<String> assetIds, String state) {
    for (final id in assetIds) {
      final row = _rows[id];
      if (row == null) continue;
      if (row.shot.onServer) {
        _rows[id] = _Row(row.shot, state, true);
      } else {
        _rows.remove(id);
      }
    }
  }

  @override
  Future<List<TrashedShot>> all() async => _where((s) => s == _trashed);

  @override
  Future<List<TrashedShot>> hidden() async => _where((s) => s != _restoring);

  List<TrashedShot> _where(bool Function(String state) test) {
    final kept = [
      for (final r in _rows.values)
        if (test(r.state)) r.shot,
    ];
    return kept..sort((a, b) {
      final byTime = b.trashedAt.compareTo(a.trashedAt);
      return byTime != 0 ? byTime : a.assetId.compareTo(b.assetId);
    });
  }

  @override
  Future<TrashOutbox> outbox() async {
    List<String> of(String state) => [
      for (final e in _rows.entries)
        if (e.value.pending && e.value.state == state) e.key,
    ];
    return TrashOutbox(
      trash: of(_trashed),
      restore: of(_restoring),
      forget: of(_forgetting),
    );
  }

  @override
  Future<void> trashSent(Iterable<String> assetIds) async {
    for (final id in assetIds) {
      final row = _rows[id];
      if (row != null && row.state == _trashed) {
        _rows[id] = _Row(row.shot, _trashed, false);
      }
    }
  }

  @override
  Future<void> restoreSent(Iterable<String> assetIds) async =>
      _deleteIn(assetIds, _restoring);

  @override
  Future<void> forgetSent(Iterable<String> assetIds) async =>
      _deleteIn(assetIds, _forgetting);

  void _deleteIn(Iterable<String> assetIds, String state) {
    for (final id in assetIds) {
      if (_rows[id]?.state == state) _rows.remove(id);
    }
  }

  @override
  Future<void> resendAll() async {
    for (final e in _rows.entries.toList()) {
      if (e.value.shot.onServer && e.value.state == _trashed) {
        _rows[e.key] = _Row(e.value.shot, _trashed, true);
      }
    }
  }
}

class _Row {
  const _Row(this.shot, this.state, this.pending);

  final TrashedShot shot;
  final String state;
  final bool pending;
}
