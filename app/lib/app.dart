import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'core/helpers.dart';
import 'core/tokens.dart';
import 'data/device/device_services.dart';
import 'data/fake_screenshot_repository.dart';
import 'data/local_merged_repository.dart';
import 'data/remote/push.dart';
import 'data/remine_store.dart';
import 'data/screenshot_repository.dart';
import 'screens/analysis_preview_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/tag_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/permission_gate.dart';
import 'screens/shell_screen.dart';
import 'screens/sync_gate.dart';

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

  /// 개발용: 'analysis'면 첫 분석 화면(멈춘 값), 'analysis-preview'·'analysis-preview-measured'면 가짜 진행으로 시작한다 (`--dart-define=START_SCREEN=...`).
  final String startScreen;

  /// 기기 모드(`--dart-define=DATA=device`)의 갤러리·OCR 서비스. null이면 가짜 데이터 모드(크롬·테스트).
  /// 기기 모드에서는 사진 권한을 먼저 확인한다. 화면의 목록 데이터는 서버 분류가 붙는 3주차 전까지 가짜 저장소다.
  final DeviceServices? device;

  @override
  State<RemineApp> createState() => _RemineAppState();

  /// [디버그] 첫 실행 게이트(사진 권한 → 이미지 동의 → 알림 안내)부터 다시 그린다. 게이트가 저장된 선택을 새로 읽는다.
  /// 저장소·동기화 기록은 그대로라 첫 분석 화면은 다시 뜨지 않는다.
  static void restartFirstRun(BuildContext context) =>
      context.findAncestorStateOfType<_RemineAppState>()?._restartFirstRun();
}

class _RemineAppState extends State<RemineApp> {
  // 기기 모드면 서버(지금은 가짜) 데이터에 기기 안 분류 결과를 합쳐 보여 준다.
  // 서버 연동(API_BASE)이 있으면 서버 저장소를, 없으면 가짜 저장소를 쓴다.
  late final RemineStore _store = RemineStore(
    _withLocal(
      widget.repository ??
          widget.device?.remote?.repository ??
          FakeScreenshotRepository(now: widget.now),
    ),
    now: widget.now,
  );

  // 알림을 눌렀을 때 화면을 띄우려고 Navigator를 바깥에서 잡는다(알림은 위젯 트리 밖에서 온다).
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<PushTarget>? _taps;
  int _firstRunGeneration = 0; // 바뀌면 게이트들을 새로 만든다([RemineApp.restartFirstRun])

  void _restartFirstRun() {
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _firstRunGeneration++);
  }

  @override
  void initState() {
    super.initState();
    // 배치(20장)가 끝날 때마다 홈·카테고리가 새로 불러온다.
    widget.device?.remote?.sync.onBatchDone = _store.refresh;
    final push = widget.device?.remote?.push;
    if (push != null) {
      push.initialTap().then((t) {
        if (t != null) _openTarget(t); // 꺼진 앱을 알림으로 켰을 때
      });
      _taps = push.taps.listen(_openTarget); // 백그라운드에서 알림을 눌렀을 때
    }
  }

  /// 관심사 알림 → 그 태그 모아보기 화면. 첫 화면이 아직 안 그려졌으면 다음 프레임에 연다.
  void _openTarget(PushTarget target) {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTarget(target));
      return;
    }
    nav.push(appRoute(nav.context, (_) => TagScreen(tag: target.tag)));
  }

  ScreenshotRepository _withLocal(ScreenshotRepository base) {
    final device = widget.device;
    return device == null
        ? base
        : LocalMergedRepository(base, device.capture.verdicts);
  }

  @override
  void dispose() {
    _taps?.cancel();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return RemineScope(
      store: _store,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
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
            : widget.startScreen == 'analysis-preview'
            ? const AnalysisPreviewScreen()
            : widget.startScreen == 'analysis-preview-measured'
            ? const AnalysisPreviewScreen(measured: true)
            : device == null
            ? const ShellScreen()
            : PermissionGate(
                key: ValueKey(_firstRunGeneration),
                reader: device.reader,
                child: ConsentGate(
                  settings: device.settings,
                  child: device.remote == null
                      ? const ShellScreen()
                      : NotificationGate(
                          remote: device.remote!,
                          settings: device.settings,
                          child: SyncGate(
                            remote: device.remote!,
                            child: const ShellScreen(),
                          ),
                        ),
                ),
              ),
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
