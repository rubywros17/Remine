import 'dart:async';

import 'package:remine/data/remote/push.dart';

/// Firebase 없이 쓰는 가짜 푸시. 토큰·권한 결과를 정해 두고, 토큰 갱신·알림 탭을 테스트가 흘려보낸다.
class FakePushClient implements PushClient {
  FakePushClient({this.currentToken = 'fcm-test-token', this.initial});

  String? currentToken;
  PushTarget? initial;
  bool grant = true;
  int permissionRequests = 0;

  final refresh = StreamController<String>.broadcast();
  final tapEvents = StreamController<PushTarget>.broadcast();

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<PushTarget?> initialTap() async => initial;

  @override
  Stream<PushTarget> get taps => tapEvents.stream;
}
