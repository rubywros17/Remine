import 'local_db.dart';

/// 기기에 두는 사용자 설정. 지금은 이미지 분석 동의 하나뿐이다.
abstract interface class SettingsStore {
  /// 이미지 분석 동의. 아직 묻지 않았으면 null, 거부면 false.
  Future<bool?> imageConsent();

  Future<void> setImageConsent(bool value);
}

const _imageConsentKey = 'image_consent';

class SqfliteSettingsStore implements SettingsStore {
  SqfliteSettingsStore(this._local);

  final LocalDb _local;

  @override
  Future<bool?> imageConsent() async {
    final rows = await (await _local.db).query(
      'setting',
      where: 'key = ?',
      whereArgs: [_imageConsentKey],
    );
    return rows.isEmpty ? null : rows.first['value'] == '1';
  }

  @override
  Future<void> setImageConsent(bool value) async {
    final db = await _local.db;
    final row = {'key': _imageConsentKey, 'value': value ? '1' : '0'};
    final updated = await db.update(
      'setting',
      row,
      where: 'key = ?',
      whereArgs: [_imageConsentKey],
    );
    if (updated == 0) await db.insert('setting', row);
  }
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this._consent]);

  bool? _consent;

  @override
  Future<bool?> imageConsent() async => _consent;

  @override
  Future<void> setImageConsent(bool value) async => _consent = value;
}
