import 'dart:io';

import 'package:flutter/widgets.dart';

import '../remote/remote_services.dart';
import 'device_capture_service.dart';
import 'device_trash.dart';
import 'gallery_reader.dart';
import 'settings_store.dart';

/// 기기 모드(`--dart-define=DATA=device`)에서 화면이 쓰는 서비스 묶음.
class DeviceServices {
  const DeviceServices({
    required this.reader,
    required this.capture,
    required this.settings,
    required this.exportDir,
    required this.trash,
    this.remote,
  });

  final GalleryReader reader;
  final DeviceCaptureService capture;
  final SettingsStore settings;
  final DeviceTrash trash;

  /// 디버그 내보내기 폴더(앱 전용 외부 저장소 — 권한 없이 쓰고 `adb pull`로 가져온다).
  final Future<Directory> Function() exportDir;

  /// 서버 연동(`--dart-define=API_BASE`). 없으면 서버 없이 기기 안 분류와 가짜 데이터만 쓴다.
  final RemoteServices? remote;
}

/// [DeviceServices]를 트리 아래로 전달한다. 가짜 데이터 모드에서는 없다(null).
class DeviceScope extends InheritedWidget {
  const DeviceScope({super.key, required this.services, required super.child});

  final DeviceServices services;

  static DeviceServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeviceScope>()?.services;

  @override
  bool updateShouldNotify(DeviceScope old) => services != old.services;
}
