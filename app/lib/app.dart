import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'core/tokens.dart';
import 'data/fake_screenshot_repository.dart';
import 'data/remine_store.dart';
import 'data/screenshot_repository.dart';
import 'screens/analysis_screen.dart';
import 'screens/shell_screen.dart';

/// 앱 루트. 3주차에 서버 연동 때는 [repository]만 API 구현으로 바꿔 넣으면 된다.
class RemineApp extends StatefulWidget {
  const RemineApp({
    super.key,
    this.repository,
    this.now,
    this.startScreen = '',
  });

  /// 지정하지 않으면 가짜 저장소.
  final ScreenshotRepository? repository;

  /// 현재 시각(테스트용 주입).
  final DateTime Function()? now;

  /// 개발용: 'analysis'면 첫 분석 화면에서 시작한다 (`--dart-define=START_SCREEN=analysis`).
  final String startScreen;

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
            : const ShellScreen(),
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
