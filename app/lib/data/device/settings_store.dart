import 'local_db.dart';

/// 기기에 두는 사용자 설정: 이미지 분석 동의, 관심사 알림 받기, 한 번만 보는 안내, 예전 스크린샷 정리.
abstract interface class SettingsStore {
  /// 이미지 분석 동의. 아직 묻지 않았으면 null, 거부면 false.
  Future<bool?> imageConsent();

  Future<void> setImageConsent(bool value);

  /// 관심사 알림 받기. 아직 고르지 않았으면 null(첫 분석 전 안내 화면이 묻는다), 끄면 false.
  /// 켜져 있을 때만 서버에 FCM 토큰이 있다.
  Future<bool?> notificationsEnabled();

  Future<void> setNotificationsEnabled(bool value);

  /// Remine 자기 캡처 판정용 기록(앱이 앞에 있던 구간, JSON). [ForegroundLog]만 읽고 쓴다. 기기 밖으로 나가지 않는다.
  Future<String?> ownCaptureLog();

  Future<void> setOwnCaptureLog(String json);

  /// 상세 화면의 "위로 밀어 삭제" 안내를 봤는지(한 번만 보여 준다).
  Future<bool> swipeTutorialSeen();

  Future<void> setSwipeTutorialSeen();

  /// [디버그] 안내를 다시 보게 '봤음' 기록만 지운다.
  Future<void> clearSwipeTutorialSeen();

  /// [디버그] 첫 실행 선택(이미지 동의·알림)만 지워 첫 실행 안내를 다시 보게 한다. 분석·전송 기록은 그대로다.
  Future<void> clearFirstRunChoices();

  /// 예전 스크린샷(최신 300장보다 오래된 것) 분석 범위: `none`(최근 300장만 — 예전 정리 안 함), `all`(전부),
  /// 또는 시작 날짜 `yyyy-MM-dd`([olderRangeStart]). 아직 고르지 않았으면 null이고, 그동안은 예전 스크린샷을 읽지 않는다.
  Future<String?> olderRangeFrom();

  Future<void> setOlderRangeFrom(String value);

  /// 고른 범위의 종류(화면에 보일 이름용). [setOlderRange]로 범위 값과 같이 저장한다. 고르지 않았으면 null.
  Future<OlderRangeKind?> olderRangeKind();

  /// 범위 고르기 화면에서 고른 범위를 저장한다. [from]은 [OlderRangeKind.year]·[OlderRangeKind.custom]의 시작 날짜.
  Future<void> setOlderRange(OlderRangeKind kind, {DateTime? from});

  /// 예전 스크린샷을 어디까지 봤는지([PhotoPosition.encode]). 처음이면 null(맨 앞부터).
  Future<String?> olderCursor();

  /// null이면 지운다(처음부터 다시).
  Future<void> setOlderCursor(String? value);

  /// 예전 스크린샷 이어서 정리하기(기본 켜짐).
  Future<bool> olderEnabled();

  Future<void> setOlderEnabled(bool value);

  /// Wi-Fi에서만 예전 스크린샷 정리(기본 켜짐).
  Future<bool> olderWifiOnly();

  Future<void> setOlderWifiOnly(bool value);

  /// 충전 중일 때만 예전 스크린샷 정리(기본 꺼짐).
  Future<bool> olderChargingOnly();

  Future<void> setOlderChargingOnly(bool value);

  /// 마지막으로 서버에서 받은 오늘 남은 예전 스크린샷 몫(표시용, 기준은 늘 서버 값). 받은 적 없으면 null.
  Future<({int remaining, DateTime? resetsAt})?> olderQuota();

  Future<void> setOlderQuota(int remaining, DateTime? resetsAt);
}

/// [SettingsStore.olderRangeFrom] 값을 해석한다: 꺼짐(null·`none`) / 전부(from null) / 그 날짜부터.
({bool enabled, DateTime? from}) olderRangeStart(String? value) {
  if (value == null || value.isEmpty || value == olderRangeNone) {
    return (enabled: false, from: null);
  }
  if (value == olderRangeAll) return (enabled: true, from: null);
  final d = DateTime.tryParse(value);
  return d == null ? (enabled: false, from: null) : (enabled: true, from: d);
}

const olderRangeAll = 'all';

/// "최근 300장"을 골랐다: 예전 스크린샷은 정리하지 않는다(고르지 않은 null과 달리 범위 고르기 화면을 다시 띄우지 않는다).
const olderRangeNone = 'none';

/// 범위 고르기 화면의 선택지.
enum OlderRangeKind {
  recent300('recent'),
  year('year'),
  all('all'),
  custom('custom');

  const OlderRangeKind(this.code);
  final String code;

  static OlderRangeKind? parse(String? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }

  /// 저장할 [SettingsStore.olderRangeFrom] 값.
  String rangeValue(DateTime? from) => switch (this) {
    recent300 => olderRangeNone,
    all => olderRangeAll,
    year || custom => ymd(from!),
  };
}

/// `yyyy-MM-dd`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [디버그] `--dart-define=OLDER_RANGE=1y`(또는 `6m`·`30d`·`all`)을 [now] 기준 범위 값으로 바꾼다. 틀린 값이면 null.
String? olderRangeFromDefine(String define, DateTime now) {
  if (define == olderRangeAll) return olderRangeAll;
  final m = RegExp(r'^(\d+)([dmy])$').firstMatch(define);
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  final from = switch (m.group(2)) {
    'd' => DateTime(now.year, now.month, now.day - n),
    'm' => DateTime(now.year, now.month - n, now.day),
    _ => DateTime(now.year - n, now.month, now.day),
  };
  return ymd(from);
}

const _imageConsentKey = 'image_consent';
const _notificationsKey = 'notifications_enabled';
const _ownCaptureLogKey = 'own_capture_log';
const _swipeTutorialKey = 'swipe_tutorial_seen';
const _olderRangeKey = 'older_range_from';
const _olderRangeKindKey = 'older_range_kind';
const _olderCursorKey = 'older_cursor';
const _olderEnabledKey = 'older_enabled';
const _olderWifiKey = 'older_wifi_only';
const _olderChargingKey = 'older_charging_only';
const _olderQuotaKey = 'older_quota';

class SqfliteSettingsStore implements SettingsStore {
  SqfliteSettingsStore(this._local);

  final LocalDb _local;

  @override
  Future<bool?> imageConsent() async {
    final v = await _get(_imageConsentKey);
    return v == null ? null : v == '1';
  }

  @override
  Future<void> setImageConsent(bool value) =>
      _put(_imageConsentKey, value ? '1' : '0');

  @override
  Future<bool?> notificationsEnabled() async {
    final v = await _get(_notificationsKey);
    return v == null ? null : v == '1';
  }

  @override
  Future<void> setNotificationsEnabled(bool value) =>
      _put(_notificationsKey, value ? '1' : '0');

  @override
  Future<String?> ownCaptureLog() => _get(_ownCaptureLogKey);

  @override
  Future<void> setOwnCaptureLog(String json) => _put(_ownCaptureLogKey, json);

  @override
  Future<bool> swipeTutorialSeen() async =>
      await _get(_swipeTutorialKey) == '1';

  @override
  Future<void> setSwipeTutorialSeen() => _put(_swipeTutorialKey, '1');

  @override
  Future<void> clearSwipeTutorialSeen() => _delete([_swipeTutorialKey]);

  @override
  Future<void> clearFirstRunChoices() =>
      _delete([_imageConsentKey, _notificationsKey]);

  @override
  Future<String?> olderRangeFrom() => _get(_olderRangeKey);

  @override
  Future<void> setOlderRangeFrom(String value) => _put(_olderRangeKey, value);

  @override
  Future<OlderRangeKind?> olderRangeKind() async =>
      OlderRangeKind.parse(await _get(_olderRangeKindKey));

  @override
  Future<void> setOlderRange(OlderRangeKind kind, {DateTime? from}) async {
    await _put(_olderRangeKey, kind.rangeValue(from));
    await _put(_olderRangeKindKey, kind.code);
  }

  @override
  Future<String?> olderCursor() => _get(_olderCursorKey);

  @override
  Future<void> setOlderCursor(String? value) =>
      value == null ? _delete([_olderCursorKey]) : _put(_olderCursorKey, value);

  @override
  Future<bool> olderEnabled() async => await _get(_olderEnabledKey) != '0';

  @override
  Future<void> setOlderEnabled(bool value) =>
      _put(_olderEnabledKey, value ? '1' : '0');

  @override
  Future<bool> olderWifiOnly() async => await _get(_olderWifiKey) != '0';

  @override
  Future<void> setOlderWifiOnly(bool value) =>
      _put(_olderWifiKey, value ? '1' : '0');

  @override
  Future<bool> olderChargingOnly() async =>
      await _get(_olderChargingKey) == '1';

  @override
  Future<void> setOlderChargingOnly(bool value) =>
      _put(_olderChargingKey, value ? '1' : '0');

  @override
  Future<({int remaining, DateTime? resetsAt})?> olderQuota() async {
    final v = await _get(_olderQuotaKey);
    final bar = v?.indexOf('|') ?? -1;
    final n = bar < 0 ? null : int.tryParse(v!.substring(0, bar));
    if (n == null) return null;
    return (remaining: n, resetsAt: DateTime.tryParse(v!.substring(bar + 1)));
  }

  @override
  Future<void> setOlderQuota(int remaining, DateTime? resetsAt) =>
      _put(_olderQuotaKey, '$remaining|${resetsAt?.toIso8601String() ?? ''}');

  Future<void> _delete(List<String> keys) async {
    final db = await _local.db;
    for (final key in keys) {
      await db.delete('setting', where: 'key = ?', whereArgs: [key]);
    }
  }

  Future<String?> _get(String key) async {
    final rows = await (await _local.db).query(
      'setting',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> _put(String key, String value) async {
    final db = await _local.db;
    final row = {'key': key, 'value': value};
    final updated = await db.update(
      'setting',
      row,
      where: 'key = ?',
      whereArgs: [key],
    );
    if (updated == 0) await db.insert('setting', row);
  }
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this._consent]);

  bool? _consent;
  bool? _notifications;
  String? _ownCaptureLog;
  bool _swipeTutorialSeen = false;

  @override
  Future<bool?> imageConsent() async => _consent;

  @override
  Future<void> setImageConsent(bool value) async => _consent = value;

  @override
  Future<bool?> notificationsEnabled() async => _notifications;

  @override
  Future<void> setNotificationsEnabled(bool value) async =>
      _notifications = value;

  @override
  Future<String?> ownCaptureLog() async => _ownCaptureLog;

  @override
  Future<void> setOwnCaptureLog(String json) async => _ownCaptureLog = json;

  @override
  Future<bool> swipeTutorialSeen() async => _swipeTutorialSeen;

  @override
  Future<void> setSwipeTutorialSeen() async => _swipeTutorialSeen = true;

  @override
  Future<void> clearSwipeTutorialSeen() async => _swipeTutorialSeen = false;

  @override
  Future<void> clearFirstRunChoices() async {
    _consent = null;
    _notifications = null;
  }

  String? olderRange;
  String? cursor;
  bool enabled = true;
  bool wifiOnly = true;
  bool chargingOnly = false;
  ({int remaining, DateTime? resetsAt})? quota;

  @override
  Future<String?> olderRangeFrom() async => olderRange;

  @override
  Future<void> setOlderRangeFrom(String value) async => olderRange = value;

  OlderRangeKind? olderKind;

  @override
  Future<OlderRangeKind?> olderRangeKind() async => olderKind;

  @override
  Future<void> setOlderRange(OlderRangeKind kind, {DateTime? from}) async {
    olderRange = kind.rangeValue(from);
    olderKind = kind;
  }

  @override
  Future<String?> olderCursor() async => cursor;

  @override
  Future<void> setOlderCursor(String? value) async => cursor = value;

  @override
  Future<bool> olderEnabled() async => enabled;

  @override
  Future<void> setOlderEnabled(bool value) async => enabled = value;

  @override
  Future<bool> olderWifiOnly() async => wifiOnly;

  @override
  Future<void> setOlderWifiOnly(bool value) async => wifiOnly = value;

  @override
  Future<bool> olderChargingOnly() async => chargingOnly;

  @override
  Future<void> setOlderChargingOnly(bool value) async => chargingOnly = value;

  @override
  Future<({int remaining, DateTime? resetsAt})?> olderQuota() async => quota;

  @override
  Future<void> setOlderQuota(int remaining, DateTime? resetsAt) async =>
      quota = (remaining: remaining, resetsAt: resetsAt);
}
