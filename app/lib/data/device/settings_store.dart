import 'local_db.dart';

/// 기기에 두는 사용자 설정: 이미지 분석 동의, 관심사 알림 받기, 한 번만 보는 안내.
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
}

const _imageConsentKey = 'image_consent';
const _notificationsKey = 'notifications_enabled';
const _ownCaptureLogKey = 'own_capture_log';
const _swipeTutorialKey = 'swipe_tutorial_seen';

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
}
