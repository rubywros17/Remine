import 'local_db.dart';

/// 기기에 두는 사용자 설정: 이미지 분석 동의, 알림 권한을 이미 물었는지.
abstract interface class SettingsStore {
  /// 이미지 분석 동의. 아직 묻지 않았으면 null, 거부면 false.
  Future<bool?> imageConsent();

  Future<void> setImageConsent(bool value);

  /// 첫 동기화 뒤 알림 권한 시트를 이미 보여 줬는지(한 번만 묻는다).
  Future<bool> notificationAsked();

  Future<void> setNotificationAsked();
}

const _imageConsentKey = 'image_consent';
const _notificationAskedKey = 'notification_asked';

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
  Future<bool> notificationAsked() async =>
      await _get(_notificationAskedKey) == '1';

  @override
  Future<void> setNotificationAsked() => _put(_notificationAskedKey, '1');

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
  bool _notificationAsked = false;

  @override
  Future<bool?> imageConsent() async => _consent;

  @override
  Future<void> setImageConsent(bool value) async => _consent = value;

  @override
  Future<bool> notificationAsked() async => _notificationAsked;

  @override
  Future<void> setNotificationAsked() async => _notificationAsked = true;
}
