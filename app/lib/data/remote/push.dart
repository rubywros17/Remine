import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../../models/category.dart';

/// 관심사 알림을 눌렀을 때 열 화면: 그 카테고리를 [tag]로 거른 목록.
/// 서버가 보내는 data는 `{type: interest, tag, category}`뿐이다(OCR 원문·요약 없음).
class PushTarget {
  const PushTarget({required this.tag, required this.category});

  final String tag;
  final Category category;

  /// 모르는 알림이거나 값이 이상하면 null(아무 화면도 열지 않는다).
  static PushTarget? fromData(Map<String, dynamic> data) {
    final tag = data['tag'];
    final code = data['category'];
    if (data['type'] != 'interest' || tag is! String || tag.isEmpty) {
      return null;
    }
    final category = Category.values.where((c) => c.code == code).firstOrNull;
    return category == null ? null : PushTarget(tag: tag, category: category);
  }

  @override
  bool operator ==(Object other) =>
      other is PushTarget && other.tag == tag && other.category == category;

  @override
  int get hashCode => Object.hash(tag, category);
}

/// 푸시 기능 묶음. 앱 코드는 이것만 보고, Firebase는 [FirebasePushClient]에만 있다(테스트는 가짜로 바꾼다).
///
/// [Dart 메모] `abstract interface class`는 자바 interface와 같다. `Stream`은 값이 여러 번 오는 이벤트
/// 흐름(Rx/Reactor의 Flux와 비슷)이고, `listen`으로 구독한다.
abstract interface class PushClient {
  /// 이 기기의 FCM 토큰. 못 받으면(오프라인·Play 서비스 없음) null — 동기화는 막지 않는다.
  Future<String?> token();

  /// FCM이 토큰을 바꿀 때마다.
  Stream<String> get tokenRefresh;

  /// 알림 권한을 묻는다(Android 13+는 시스템 창). 허용됐으면 true.
  /// 이미 영구 거부했으면 창 없이 false — 이때는 [openSystemSettings]로 안내한다.
  Future<bool> requestPermission();

  /// 지금 알림이 허용돼 있는지(묻지 않는다). 사용자가 휴대폰 설정에서 끄면 false.
  Future<bool> permissionGranted();

  /// 이 앱의 휴대폰 알림 설정 화면을 연다.
  Future<void> openSystemSettings();

  /// 앱이 꺼진 상태에서 알림을 눌러 켜졌으면 그 알림.
  Future<PushTarget?> initialTap();

  /// 앱이 백그라운드일 때 알림을 눌렀을 때마다.
  Stream<PushTarget> get taps;
}

/// ponytail: firebase_messaging 17은 getToken/onTokenRefresh를 deprecated로 두고 FID 등록(register/onRegistered)을 권한다.
/// FID로 바꾸려면 서버 Admin SDK의 발송 대상도 함께 바꿔야 해서, 아직 동작하는 등록 토큰 방식을 쓴다.
class FirebasePushClient implements PushClient {
  FirebasePushClient([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken(); // ignore: deprecated_member_use
    } catch (_) {
      return null;
    }
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  // 휴대폰 설정 열기는 플러그인 없이 MainActivity.kt의 채널 하나로 한다.
  static const _settings = MethodChannel('remine/settings');

  @override
  Future<bool> requestPermission() async =>
      _allowed(await _messaging.requestPermission());

  @override
  Future<bool> permissionGranted() async =>
      _allowed(await _messaging.getNotificationSettings());

  @override
  Future<void> openSystemSettings() =>
      _settings.invokeMethod<void>('openNotificationSettings');

  static bool _allowed(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized ||
      s.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<PushTarget?> initialTap() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : PushTarget.fromData(m.data);
  }

  @override
  Stream<PushTarget> get taps => FirebaseMessaging.onMessageOpenedApp
      .map((m) => PushTarget.fromData(m.data))
      .where((t) => t != null)
      .cast<PushTarget>();
}
