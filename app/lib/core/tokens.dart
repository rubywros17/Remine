import 'package:flutter/material.dart';

// 디자인 토큰(색·폰트·모서리·간격·모션)은 이 파일 한 곳에만 둔다. 값의 근거는 docs/design.md.
//
// [Dart 메모] `abstract final class`는 "인스턴스를 만들 수도, 상속할 수도 없는" 클래스다.
// 상수와 static 메서드만 모아 두는 네임스페이스(자바의 final class + private 생성자)로 쓴다.

/// 색. 셀라돈·레몬 위 글자는 항상 [ink].
abstract final class AppColors {
  static const background = Color(0xFFFBFBF8);
  static const ink = Color(0xFF111111);
  static const inkSub = Color(0xFF6F6F71); // 칩·셀라돈 위에는 쓰지 않는다(대비 부족)
  static const darkGray = Color(0xFF4A4B4E); // 위 글자는 흰색
  static const celadon = Color(0xFF7DC4CE); // 면·버튼용
  static const celadonDeep = Color(0xFF3E8D98); // 바탕 위 큰 숫자 전용
  static const celadonSoft = Color(0xFFDDEFF2);
  static const lemon = Color(0xFFEDE7B3);
  static const chip = Color(0xFFEEF0F0);
  static const border = Color(0xFFE1E3E3);
  static const white = Color(0xFFFFFFFF);
}

/// 모서리 반경.
abstract final class AppRadii {
  static const double card = 28;
  static const double sheet = 30;
  static const double tile = 18;
  static const double pill = 999;
}

/// 간격(4 단위)과 화면 좌우 여백.
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double screenPadding = 22;
}

/// 글자 스타일. 한글은 Pretendard, 숫자·영문은 Space Grotesk.
abstract final class AppText {
  static const _kr = 'Pretendard';
  static const _num = 'SpaceGrotesk';

  // 숫자 폰트는 가변 폰트라 굵기를 fontVariations로도 지정해야 실제로 반영된다.
  static TextStyle _numeric(double size, double weight, Color color) => TextStyle(
        fontFamily: _num,
        fontSize: size,
        height: 1.0,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation.weight(weight)],
        color: color,
      );

  static const display = TextStyle(
      fontFamily: _kr, fontSize: 30, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const title = TextStyle(
      fontFamily: _kr, fontSize: 36, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const sectionTitle = TextStyle(
      fontFamily: _kr, fontSize: 18, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const cardTitle = TextStyle(
      fontFamily: _kr, fontSize: 20, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const body = TextStyle(
      fontFamily: _kr, fontSize: 15, height: 1.5, fontWeight: FontWeight.w400, color: AppColors.ink);
  static const label = TextStyle(
      fontFamily: _kr, fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const caption = TextStyle(
      fontFamily: _kr, fontSize: 12, height: 1.3, fontWeight: FontWeight.w400, color: AppColors.inkSub);

  static TextStyle numHero({Color color = AppColors.ink, double size = 88}) => _numeric(size, 700, color);
  static TextStyle numXL({Color color = AppColors.ink}) => _numeric(56, 700, color);
  static TextStyle numBadge({Color color = AppColors.ink}) => _numeric(13, 600, color);
  static TextStyle brand({Color color = AppColors.ink}) => _numeric(20, 700, color);
}

enum MotionDuration { fast, base, slow }

/// 모션 토큰. "애니메이션 줄이기"(`MediaQuery.disableAnimations`)가 켜져 있으면 모든 시간이 0이다.
abstract final class AppMotion {
  static const _durations = {
    MotionDuration.fast: Duration(milliseconds: 120),
    MotionDuration.base: Duration(milliseconds: 240),
    MotionDuration.slow: Duration(milliseconds: 420),
  };

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve exit = Curves.easeInCubic;

  /// 시트·눌림 반응용 스프링.
  static const spring = SpringDescription(mass: 1, stiffness: 300, damping: 22);

  static bool reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, MotionDuration d) =>
      reduced(context) ? Duration.zero : _durations[d]!;
}
