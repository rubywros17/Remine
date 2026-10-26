import 'local_db.dart';

/// 기기에 두는 사용자 설정: 이미지 분석 동의, 관심사 알림 받기.
abstract interface class SettingsStore {
  /// 이미지 분석 동의. 아직 묻지 않았으면 null, 거부면 false.
  Future<bool?> imageConsent();

  Future<void> setImageConsent(bool value);

  /// 관심사 알림 받기. 아직 고르지 않았으면 null(첫 분석 뒤 안내 화면이 묻는다), 끄면 false.
  /// 켜져 있을 때만 서버에 FCM 토큰이 있다.
  Future<bool?> notificationsEnabled();

  Future<void> setNotificationsEnabled(bool value);
}

const _imageConsentKey = 'image_consent';
const _notificationsKey = 'notifications_enabled';

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

  @override
  Future<bool?> imageConsent() async => _consent;

  @override
  Future<void> setImageConsent(bool value) async => _consent = value;

  @override
  Future<bool?> notificationsEnabled() async => _notifications;

  @override
  Future<void> setNotificationsEnabled(bool value) async =>
      _notifications = value;
}
