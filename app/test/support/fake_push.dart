import 'dart:async';

import 'package:remine/data/remote/push.dart';

/// Firebase 없이 쓰는 가짜 푸시. 토큰·권한 결과를 정해 두고, 토큰 갱신·알림 탭을 테스트가 흘려보낸다.
class FakePushClient implements PushClient {
  FakePushClient({this.currentToken = 'fcm-test-token', this.initial});

  String? currentToken;
  PushTarget? initial;

  /// 권한 창에서 허용할지. [granted]는 지금 허용돼 있는지(묻지 않음).
  bool grant = true;
  bool granted = false;
  int permissionRequests = 0;
  int settingsOpened = 0;

  final refresh = StreamController<String>.broadcast();
  final tapEvents = StreamController<PushTarget>.broadcast();

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted = grant;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<void> openSystemSettings() async => settingsOpened++;

  @override
  Future<PushTarget?> initialTap() async => initial;

  @override
  Stream<PushTarget> get taps => tapEvents.stream;
}
