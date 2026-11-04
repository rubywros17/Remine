import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/category.dart';

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

  /// 휴지통 기준선을 넘었을 때 아이콘 배경(원)과 아이콘.
  static const trashActiveBackground = Color(0xFF111111);
  static const trashActiveIcon = lemon;

  /// 선택된 사진을 덮는 어둡게(ink 15%). 사진은 칸 안에서 [AppGesture.selectedPhotoScale]배로 줄어든다.
  static const selectionDim = Color(0x26111111);

  /// 상세 이미지 카드의 부드러운 그림자.
  static const cardShadow = Color(0x40000000);

  /// 선택 전 빈 원의 얇은 그림자(밝은 사진 위에서도 보이게).
  static const selectionRingShadow = Color(0x59111111);
}

/// 카테고리 색(홈 비율 막대의 칸 · 알약 앞 점). 기존 토큰과 같은 값은 그 토큰을 그대로 쓴다.
abstract final class AppCategoryColors {
  static Color of(Category c) => switch (c) {
    Category.shopping => AppColors.celadon,
    Category.entertainment => AppColors.lemon,
    Category.place => AppColors.darkGray,
    Category.info => const Color(0xFFB9D6DB),
    Category.chat => AppBrain.subtitle,
    Category.schedule => const Color(0xFFF6C6B5),
    Category.etc => AppColors.border,
  };

  /// 밝은 색 점은 바탕과 구분되게 옅은 테두리(ink 15%)를 두른다. 장소(다크그레이)만 필요 없다.
  static const dotOutline = Color(0x26111111);
  static bool needsOutline(Category c) => c != Category.place;

  static const double dotSize = 9;
  static const double barHeight = 30;
  static const double barGap = 2;
  static const double barMinSegment = 8; // 1장이어도 보이는 최소 칸 폭

  /// "분석 제외" 알약 점선 테두리(inkSub): 선 길이 · 빈칸.
  static const double excludedDash = 4;
  static const double excludedDashGap = 3;
}

/// 관심사 탭 진입 "머릿속 캡처 지도"(디자인 캔버스 4안 · 관심사 · 머릿속 캡처 지도). 배경은 [AppColors.darkGray].
abstract final class AppBrain {
  static const cerebrum = Color(0xFF56676B); // 대뇌 안쪽 채움
  static const outline = AppColors.celadon; // 윤곽·연결선
  static const fold = Color(0x807DC4CE); // 주름: 셀라돈 50%
  static const cerebellum = Color(0xFF4E9CA7);
  static const brainstem = AppColors.celadonDeep;
  static const subtitle = Color(0xFFC9CBCC); // 어두운 바탕 위 보조 글자

  /// 전체 길이(윤곽 → … → 잊은 관심사가 깨어남)와 목록으로 넘어가는 크로스페이드.
  static const duration = Duration(seconds: 3);
  static const crossfade = Duration(milliseconds: 400);

  /// 지도에 올리는 관심사 수(많이 캡처한 순). 나머지는 목록에서만.
  static const maxNodes = 7;
}

/// 관심사 카드(홈·관심사 탭). 한 화면(360×800)에 3장이 들어가는 높이.
abstract final class AppInterestCard {
  static const double minHeight = 168;

  /// 콜라주 위 원형 스티커 "19 / SHOTS": 지름, 기울기(10°).
  static const double shotsSize = 58;
  static const double shotsTilt = 10 * math.pi / 180;

  /// 카드 뒤 큰 숫자 워터마크: 크기, 외곽선 두께, 색(흰색 14%).
  static const double watermarkSize = 132;
  static const double watermarkStroke = 1.4;
  static const watermarkColor = Color(0x24FFFFFF);

  /// 왼쪽 아래 점 게이지: 이 장수 이상이면 점 하나씩 더(5칸). 잊은 관심사는 레몬 1칸.
  static const gaugeSteps = [3, 6, 10, 15, 20];
  static const double gaugeDot = 7;
  static const gaugeEmpty = Color(0x40FFFFFF); // 빈 칸: 흰색 25%

  /// 잊은 관심사 레몬 테두리 두께.
  static const double forgottenBorder = 2;
}

/// 상세 화면의 이미지 카드·배경 값. 값의 근거는 docs/design.md.
abstract final class AppDetail {
  /// 이미지 카드 최대 폭(영역 폭 비율), 흰 테두리 두께(px), 상단 바 아래 최소 여백(px), 기울기(-2°, 라디안).
  static const double cardMaxWidthFraction = 0.78;
  static const double cardBorder = 6;
  static const double cardTopGap = 16;
  static const double cardTilt = -2 * math.pi / 180;
}

/// 가짜 썸네일(색 블록)용 색 쌍: (바탕, 안쪽 블록). 실제 스크린샷 대신 쓴다.
abstract final class AppThumbs {
  static const palette = <(Color, Color)>[
    (Color(0xFF9ED0D9), Color(0xFF5FA8B1)),
    (Color(0xFFE6E6E6), Color(0xFFB5B5B5)),
    (Color(0xFFDDE9EA), Color(0xFF9FD0D9)),
    (Color(0xFF7DC4CE), Color(0xFFDBE8EA)),
    (Color(0xFFCCCCCF), Color(0xFF8F8F91)),
    (Color(0xFFEDE7B3), Color(0xFFFBFBF8)),
  ];
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
  static TextStyle _numeric(double size, double weight, Color color) =>
      TextStyle(
        fontFamily: _num,
        fontSize: size,
        height: 1.0,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation.weight(weight)],
        color: color,
      );

  static const display = TextStyle(
    fontFamily: _kr,
    fontSize: 30,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const title = TextStyle(
    fontFamily: _kr,
    fontSize: 36,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const sectionTitle = TextStyle(
    fontFamily: _kr,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const cardTitle = TextStyle(
    fontFamily: _kr,
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontFamily: _kr,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );
  static const label = TextStyle(
    fontFamily: _kr,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: _kr,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: AppColors.inkSub,
  );

  static TextStyle numHero({Color color = AppColors.ink, double size = 88}) =>
      _numeric(size, 700, color);
  static TextStyle numXL({Color color = AppColors.ink}) =>
      _numeric(56, 700, color);
  static TextStyle numBadge({Color color = AppColors.ink}) =>
      _numeric(13, 600, color);
  static TextStyle brand({Color color = AppColors.ink}) =>
      _numeric(20, 700, color);
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

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, MotionDuration d) =>
      reduced(context) ? Duration.zero : _durations[d]!;
}

/// 상세 화면 제스처 값(좌우 넘기기 · 아래로 닫기 · 위로 던져 휴지통). 값의 근거와 동작은 docs/design.md.
/// 손가락 감각은 실기기에서 조정하므로 숫자는 전부 여기 한 곳에 둔다.
abstract final class AppGesture {
  /// 측정 화면에서 선택한 사진이 칸 안에서 줄어드는 배율.
  static const double selectedPhotoScale = 0.86;

  /// 위로 끌어 이 높이(화면 높이 비율)를 넘으면 휴지통 기준선 통과.
  static const double trashLineFraction = 1 / 3;

  /// 놓을 때 위쪽 속도(px/s)가 이 값 이상이면 기준선 전이라도 휴지통으로 던진 것으로 본다.
  static const double trashFlingVelocity = 1200;

  /// 휴지통 플링으로 인정하려면 최소한 이만큼(px)은 끌어야 한다(스치기 방지).
  static const double trashFlingMinDistance = 24;

  /// 끄는 거리에 비례해 어두워지는 배경(다크그레이)의 최대 불투명도.
  static const double trashDimMaxOpacity = 0.72;

  /// 끌수록 카드가 줄어드는 최소 배율, 기울어지는 최대 각도(라디안).
  static const double trashCardMinScale = 0.86;
  static const double trashCardTilt = 0.06;

  /// 휴지통 아이콘이 끌수록 커지는 범위.
  static const double trashIconMinScale = 0.6;
  static const double trashIconMaxScale = 1.4;

  /// 빨려 들어간 카드의 최종 배율.
  static const double trashSuckScale = 0.1;

  /// 아래로 쓸어 닫기: 화면 높이 비율 또는 아래쪽 속도(px/s).
  static const double dismissFraction = 0.18;
  static const double dismissFlingVelocity = 800;

  /// 휴지통으로 옮긴 뒤 "되돌리기"를 보여주는 시간.
  static const Duration undoDuration = Duration(seconds: 4);
}
