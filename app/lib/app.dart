import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'core/tokens.dart';
import 'data/device/device_services.dart';
import 'data/fake_screenshot_repository.dart';
import 'data/remine_store.dart';
import 'data/screenshot_repository.dart';
import 'screens/analysis_screen.dart';
import 'screens/permission_gate.dart';
import 'screens/shell_screen.dart';

/// 앱 루트. 3주차에 서버 연동 때는 [repository]만 API 구현으로 바꿔 넣으면 된다.
class RemineApp extends StatefulWidget {
  const RemineApp({
    super.key,
    this.repository,
    this.now,
    this.startScreen = '',
    this.device,
  });

  /// 지정하지 않으면 가짜 저장소.
  final ScreenshotRepository? repository;

  /// 현재 시각(테스트용 주입).
  final DateTime Function()? now;

  /// 개발용: 'analysis'면 첫 분석 화면에서 시작한다 (`--dart-define=START_SCREEN=analysis`).
  final String startScreen;

  /// 기기 모드(`--dart-define=DATA=device`)의 갤러리·OCR 서비스. null이면 가짜 데이터 모드(크롬·테스트).
  /// 기기 모드에서는 사진 권한을 먼저 확인한다. 화면의 목록 데이터는 서버 분류가 붙는 3주차 전까지 가짜 저장소다.
  final DeviceServices? device;

  @override
  State<RemineApp> createState() => _RemineAppState();
}

class _RemineAppState extends State<RemineApp> {
  late final RemineStore _store = RemineStore(
    widget.repository ?? FakeScreenshotRepository(now: widget.now),
    now: widget.now,
  );

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return RemineScope(
      store: _store,
      child: MaterialApp(
        title: 'Remine',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        // 웹(크롬)에서도 마우스로 가로 스크롤(태그 칩 줄)이 되게 한다.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        home: widget.startScreen == 'analysis'
            ? const AnalysisScreen()
            : device == null
            ? const ShellScreen()
            : PermissionGate(reader: device.reader, child: const ShellScreen()),
        builder: device == null
            ? null
            : (context, child) => DeviceScope(services: device, child: child!),
      ),
    );
  }
}

final ThemeData _theme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Pretendard',
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.light(
    primary: AppColors.darkGray,
    onPrimary: AppColors.white,
    surface: AppColors.background,
    onSurface: AppColors.ink,
  ),
  textTheme: Typography.blackMountainView.apply(
    fontFamily: 'Pretendard',
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  ),
  splashFactory: NoSplash.splashFactory, // 눌림 반응은 PressableScale이 맡는다
  highlightColor: Colors.transparent,
);
