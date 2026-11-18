import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../device/local_db.dart';

/// 서버 동기화 상태 한 줄: 캡처(asset id)가 서버에 어떻게 반영됐는지.
/// 동기화 기록 상태. 모두 기기 로컬 DB에만 있다.
enum SyncStatusCode {
  synced,
  failed,

  /// 기기에서 분류가 끝나 서버로 보내지 않은 캡처(민감·금융·메신저·글자 없음). 다음 실행에서 다시 처리하지 않으려는
  /// 기록일 뿐, 이 상태의 asset id는 어떤 요청에도 싣지 않는다.
  deviceOnly,
}

class SyncEntry {
  const SyncEntry({
    required this.assetId,
    required this.modifiedAt,
    required this.status,
    this.serverId,
  });

  final String assetId;

  /// 보낸 시점의 사진 수정 시각. 달라지면 바뀐 캡처라 다시 보낸다.
  final int modifiedAt;
  final SyncStatusCode status;

  /// 서버 id. 목록을 받아 봐야 알 수 있어 처음에는 null.
  final int? serverId;
}

/// 서버 연동 상태를 기기에 둔다: 기기 id, 첫 분석 완료 여부, asset id ↔ 서버 id 매핑, 마지막으로 받은 목록·요약.
/// 캐시는 서버 응답 JSON(카테고리·태그·요약)이라 OCR 원문은 없다.
abstract interface class RemoteStateStore {
  Future<int?> deviceId();
  Future<void> setDeviceId(int id);

  /// 이 기기를 서버에 처음 등록한(또는 이 기능이 생긴 뒤 처음 동기화한) 시각. 이 뒤에 찍은 캡처가 "새 스크린샷"이라
  /// 개수 제한 없이 읽는다. 아직이면 null. 서버가 기기를 잊어도([clear]) 그대로 둔다.
  Future<DateTime?> registeredAt();
  Future<void> setRegisteredAt(DateTime at);

  /// 예전 스크린샷 경로에서 이 캡처가 실패한 횟수(실행마다 한 번, 하루 한도 초과는 세지 않음). 없으면 0.
  /// 여러 번 실패한 캡처는 건너뛰고 커서를 넘긴다(계속 실패하는 한 장에서 영원히 멈추지 않게).
  Future<int> olderFailures(String assetId);

  /// 0이면 기록을 지운다.
  Future<void> setOlderFailures(String assetId, int count);

  /// 첫 분석 화면을 이미 거쳤는지.
  Future<bool> firstSyncDone();
  Future<void> setFirstSyncDone();

  Future<SyncEntry?> entry(String assetId);
  Future<void> putEntry(SyncEntry entry);

  /// 서버에서 지운 캡처의 전송 기록을 없앤다([RemineApi.forget] 뒤).
  Future<void> removeEntries(Iterable<String> assetIds);

  /// 서버 목록에서 본 (asset id → 서버 id)를 매핑에 채운다.
  Future<void> linkServerIds(Map<String, int> idsByAsset);
  Future<int> failedCount();

  Future<String?> cached(String key);
  Future<void> putCache(String key, String json);

  /// 서버가 이 기기를 잊었을 때(서버 DB 초기화): **서버 쪽 기록만** 지운다(기기 id·전송 기록·응답 캐시).
  /// 첫 분석 완료는 남긴다 — 사용자가 한 일이 아니므로 첫 분석 화면을 다시 띄우지 않고, 재전송은 홈 배너로만 보인다.
  /// (알림 선택·이미지 동의는 [SettingsStore]에 있어 여기서 건드리지 않는다.)
  Future<void> clear();
}

class SqfliteRemoteStateStore implements RemoteStateStore {
  SqfliteRemoteStateStore(this._local);

  final LocalDb _local;

  Future<Database> get _db => _local.db;

  Future<String?> _setting(String key) async {
    final rows = await (await _db).query(
      'setting',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _putSetting(String key, String value) async =>
      (await _db).insert('setting', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<int?> deviceId() async {
    final v = await _setting('device_id');
    return v == null ? null : int.tryParse(v);
  }

  @override
  Future<void> setDeviceId(int id) => _putSetting('device_id', '$id');

  @override
  Future<DateTime?> registeredAt() async {
    final v = await _setting('registered_at');
    return v == null ? null : DateTime.tryParse(v);
  }

  @override
  Future<void> setRegisteredAt(DateTime at) =>
      _putSetting('registered_at', at.toIso8601String());

  // 실패한 캡처는 드물어 작은 JSON 하나로 둔다(asset id → 횟수). 성공하거나 건너뛰면 지워 커지지 않는다.
  static const _olderFailuresKey = 'older_failures';

  Future<Map<String, int>> _olderFailureMap() async {
    final v = await _setting(_olderFailuresKey);
    if (v == null) return {};
    try {
      return (jsonDecode(v) as Map<String, dynamic>).map(
        (k, n) => MapEntry(k, (n as num).toInt()),
      );
    } catch (_) {
      return {}; // 망가진 값이면 처음부터 센다
    }
  }

  @override
  Future<int> olderFailures(String assetId) async =>
      (await _olderFailureMap())[assetId] ?? 0;

  @override
  Future<void> setOlderFailures(String assetId, int count) async {
    final map = await _olderFailureMap();
    if (count <= 0 && !map.containsKey(assetId)) return;
    if (count <= 0) {
      map.remove(assetId);
    } else {
      map[assetId] = count;
    }
    await _putSetting(_olderFailuresKey, jsonEncode(map));
  }

  @override
  Future<bool> firstSyncDone() async =>
      await _setting('first_sync_done') == '1';

  @override
  Future<void> setFirstSyncDone() => _putSetting('first_sync_done', '1');

  @override
  Future<SyncEntry?> entry(String assetId) async {
    final rows = await (await _db).query(
      'server_map',
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SyncEntry(
      assetId: assetId,
      modifiedAt: r['modified_at'] as int,
      status: SyncStatusCode.values.byName(r['status'] as String),
      serverId: r['server_id'] as int?,
    );
  }

  @override
  Future<void> putEntry(SyncEntry e) async {
    final db = await _db;
    final existing = await entry(e.assetId);
    await db.insert('server_map', {
      'asset_id': e.assetId,
      'server_id': e.serverId ?? existing?.serverId,
      'modified_at': e.modifiedAt,
      'status': e.status.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeEntries(Iterable<String> assetIds) async {
    final db = await _db;
    final batch = db.batch();
    for (final id in assetIds) {
      batch.delete('server_map', where: 'asset_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> linkServerIds(Map<String, int> idsByAsset) async {
    final db = await _db;
    final batch = db.batch();
    idsByAsset.forEach((asset, id) {
      batch.update(
        'server_map',
        {'server_id': id},
        where: 'asset_id = ?',
        whereArgs: [asset],
      );
    });
    await batch.commit(noResult: true);
  }

  @override
  Future<int> failedCount() async => Sqflite.firstIntValue(
    await (await _db).rawQuery(
      'SELECT COUNT(*) FROM server_map WHERE status = ?',
      [SyncStatusCode.failed.name],
    ),
  )!;

  @override
  Future<String?> cached(String key) async {
    final rows = await (await _db).query(
      'server_cache',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['json'] as String;
  }

  @override
  Future<void> putCache(String key, String json) async =>
      (await _db).insert('server_cache', {
        'key': key,
        'json': json,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> clear() async {
    final db = await _db;
    await db.delete('server_map');
    await db.delete('server_cache');
    await db.delete(
      'setting',
      where: 'key IN (?, ?)',
      whereArgs: ['device_id', _olderFailuresKey],
    );
  }
}

class InMemoryRemoteStateStore implements RemoteStateStore {
  int? _deviceId;
  DateTime? registered;

  @override
  Future<DateTime?> registeredAt() async => registered;

  @override
  Future<void> setRegisteredAt(DateTime at) async => registered = at;

  final Map<String, int> olderFailureCounts = {};

  @override
  Future<int> olderFailures(String assetId) async =>
      olderFailureCounts[assetId] ?? 0;

  @override
  Future<void> setOlderFailures(String assetId, int count) async => count <= 0
      ? olderFailureCounts.remove(assetId)
      : olderFailureCounts[assetId] = count;

  bool _first = false;
  final Map<String, SyncEntry> _entries = {};
  final Map<String, String> _cache = {};

  @override
  Future<int?> deviceId() async => _deviceId;

  @override
  Future<void> setDeviceId(int id) async => _deviceId = id;

  @override
  Future<bool> firstSyncDone() async => _first;

  @override
  Future<void> setFirstSyncDone() async => _first = true;

  @override
  Future<SyncEntry?> entry(String assetId) async => _entries[assetId];

  @override
  Future<void> putEntry(SyncEntry e) async => _entries[e.assetId] = SyncEntry(
    assetId: e.assetId,
    modifiedAt: e.modifiedAt,
    status: e.status,
    serverId: e.serverId ?? _entries[e.assetId]?.serverId,
  );

  @override
  Future<void> removeEntries(Iterable<String> assetIds) async =>
      assetIds.forEach(_entries.remove);

  @override
  Future<void> linkServerIds(Map<String, int> idsByAsset) async {
    idsByAsset.forEach((asset, id) {
      final e = _entries[asset];
      if (e != null) {
        _entries[asset] = SyncEntry(
          assetId: asset,
          modifiedAt: e.modifiedAt,
          status: e.status,
          serverId: id,
        );
      }
    });
  }

  @override
  Future<int> failedCount() async =>
      _entries.values.where((e) => e.status == SyncStatusCode.failed).length;

  @override
  Future<String?> cached(String key) async => _cache[key];

  @override
  Future<void> putCache(String key, String json) async => _cache[key] = json;

  @override
  Future<void> clear() async {
    _deviceId = null;
    _entries.clear();
    _cache.clear();
    olderFailureCounts.clear();
  }
}
