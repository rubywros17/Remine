import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tokens.dart';

/// 앱 시작 인트로: 찰칵 → 모서리가 모여 앱 아이콘 → 원으로 열려 [child]가 드러난다.
///
/// [child](앱 화면)는 처음부터 만들어 두고 인트로는 위에 덮기만 한다 — 동기화·로딩이 기다리지 않는다.
/// State가 앱 프로세스 동안 살아 있으므로 백그라운드에서 돌아올 때는 다시 나오지 않는다.
/// 탭하면 원으로 열기로 건너뛰고, 애니메이션 줄이기가 켜져 있으면 아예 그리지 않는다.
///
/// 글자(re·mine)는 아이콘에서 잘라 낸 마스크 이미지에 색을 입히고(폰트 렌더 차이 없음),
/// 모서리·콜론 점은 코드로 그린다. 크기는 [IntroGeometry](아이콘 1024 기준)를 화면 크기로 줄인 값.
class AppIntro extends StatefulWidget {
  const AppIntro({super.key, required this.child});

  final Widget child;

  static const overlayKey = ValueKey('intro-overlay');

  @override
  State<AppIntro> createState() => _AppIntroState();
}

// [Dart 메모] `with SingleTickerProviderStateMixin`은 AnimationController에 화면 갱신 신호(vsync)를 주는 믹스인.
class _AppIntroState extends State<AppIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.introTotal)
        ..addListener(_maybeSnap)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) setState(() => _done = true);
        });

  bool _started = false;
  bool _done = false;
  bool _snapped = false;

  double get _ms => _c.value * AppMotion.introTotalMs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _done = true;
    } else {
      _c.forward();
    }
  }

  void _maybeSnap() {
    if (_snapped || _ms < AppMotion.introFlashMs) return;
    _snapped = true;
    HapticFeedback.lightImpact();
  }

  void _skip() {
    if (_ms >= AppMotion.introRevealStartMs) return;
    _snapped = true; // 찰칵 전에 건너뛰면 햅틱도 없다
    _c.forward(from: AppMotion.introRevealStartMs / AppMotion.introTotalMs);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 끝나도 Stack은 그대로 두고 덮개만 뺀다 — child 자리가 바뀌면 앱 화면 상태(내비게이터)가 새로 만들어진다.
    return Stack(
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            key: AppIntro.overlayKey,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _overlay(context, _ms),
            ),
          ),
      ],
    );
  }

  Widget _overlay(BuildContext context, double t) {
    final screen = MediaQuery.sizeOf(context);
    final g = IntroLayout(screen, MediaQuery.paddingOf(context));
    final revealing = t >= AppMotion.introRevealStartMs;
    final gather = AppMotion.introGather.transform(
      _seg(t, AppMotion.introGatherStartMs, AppMotion.introGatherEndMs),
    );
    final logo = Curves.easeOut.transform(
      _seg(t, AppMotion.introGatherEndMs, AppMotion.introLogoEndMs),
    );
    final fade =
        1 -
        _seg(
          t,
          AppMotion.introRevealStartMs,
          AppMotion.introRevealStartMs + AppMotion.introFadeOutMs,
        );
    final hole =
        AppMotion.introGather.transform(
          _seg(t, AppMotion.introRevealStartMs, AppMotion.introTotalMs),
        ) *
        screen.longestSide; // 대각선 절반보다 크면 다 열린 것
    final flash =
        AppMotion.introFlashOpacity *
        (t < AppMotion.introFlashMs
            ? 0
            : 1 -
                  _seg(
                    t,
                    AppMotion.introFlashMs,
                    AppMotion.introFlashMs + AppMotion.introFlashFadeMs,
                  ));
    final k = g.scale;

    Widget dot(String name, Offset c, int startMs) {
      final pop = Curves.easeOutBack.transform(
        _seg(t, startMs, startMs + AppMotion.introDotPopMs),
      );
      const r = IntroGeometry.dotRadius;
      return Positioned.fromRect(
        rect: g.toScreen(Rect.fromCircle(center: c, radius: r)),
        child: Transform.scale(
          scale: pop,
          child: DecoratedBox(
            key: ValueKey('intro-$name'),
            decoration: const BoxDecoration(
              color: IntroColors.colon,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    Widget glyph(String name, Rect r, Color color) => Positioned.fromRect(
      rect: g.toScreen(r),
      child: Image.asset(
        'assets/intro/$name.png',
        key: ValueKey('intro-$name'),
        fit: BoxFit.fill,
        color: color,
        colorBlendMode: BlendMode.srcIn, // 흰 마스크 → 이 색
        filterQuality: FilterQuality.medium,
      ),
    );

    return IgnorePointer(
      ignoring: revealing, // 열리는 동안은 아래 화면을 바로 만질 수 있다
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        // 인트로 동안 상태바·내비게이션바도 차콜. 덮개가 빠지면 원래 화면 설정으로 돌아간다.
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: IntroColors.background,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: IntroColors.background,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _HolePainter(hole))),
              Opacity(
                opacity: fade,
                child: Stack(
                  children: [
                    for (final c in IntroCorner.values)
                      Positioned.fromRect(
                        rect: Rect.lerp(
                          g.startCorner(c),
                          g.endCorner(c),
                          gather,
                        )!,
                        child: CustomPaint(
                          key: ValueKey('intro-corner-${c.name}'),
                          painter: IntroCornerPainter(
                            corner: c,
                            stroke: IntroGeometry.stroke * k,
                            radius: IntroGeometry.radius * k,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: logo,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * logo, // 화면 가운데 = 아이콘 가운데 기준
                          child: Stack(
                            children: [
                              glyph('re', IntroGeometry.re, IntroColors.re),
                              glyph(
                                'mine',
                                IntroGeometry.mine,
                                IntroColors.mine,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    dot(
                      'dot-top',
                      IntroGeometry.dotTop,
                      AppMotion.introGatherEndMs,
                    ),
                    dot(
                      'dot-bottom',
                      IntroGeometry.dotBottom,
                      AppMotion.introGatherEndMs + AppMotion.introDotPopMs ~/ 2,
                    ),
                  ],
                ),
              ),
              if (flash > 0)
                Positioned.fill(
                  child: ColoredBox(
                    color: IntroColors.flash.withValues(alpha: flash),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [t]가 [a] ~ [b] 구간에서 어디쯤인지(0~1).
double _seg(double t, int a, int b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

enum IntroCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 화면 위의 인트로 배치. 아이콘(한 변 1024)을 [scale]배로 줄여 화면 가운데 놓는다.
class IntroLayout {
  IntroLayout(this.screen, this.padding)
    : scale =
          math.min(
            screen.width * IntroGeometry.frameShare,
            IntroGeometry.frameMax,
          ) /
          IntroGeometry.frame;

  final Size screen;
  final EdgeInsets padding;
  final double scale;

  /// 아이콘 좌표(1024 기준) → 화면 좌표.
  Rect toScreen(Rect icon) {
    final origin =
        screen.center(Offset.zero) -
        const Offset(IntroGeometry.icon / 2, IntroGeometry.icon / 2) * scale;
    return Rect.fromLTWH(
      origin.dx + icon.left * scale,
      origin.dy + icon.top * scale,
      icon.width * scale,
      icon.height * scale,
    );
  }

  Rect get frame => toScreen(
    const Rect.fromLTWH(
      IntroGeometry.frameLeft,
      IntroGeometry.frameLeft,
      IntroGeometry.frame,
      IntroGeometry.frame,
    ),
  );

  Rect endCorner(IntroCorner c) => _cornerIn(frame, c);

  /// 처음: 안전 영역 네 귀퉁이(뷰파인더처럼).
  Rect startCorner(IntroCorner c) => _cornerIn(
    padding.deflateRect(Offset.zero & screen).deflate(IntroGeometry.startInset),
    c,
  );

  Rect _cornerIn(Rect box, IntroCorner c) {
    final a = IntroGeometry.arm * scale;
    return Rect.fromLTWH(
      c == IntroCorner.topLeft || c == IntroCorner.bottomLeft
          ? box.left
          : box.right - a,
      c == IntroCorner.topLeft || c == IntroCorner.topRight
          ? box.top
          : box.bottom - a,
      a,
      a,
    );
  }
}

/// 모서리 한 조각: 둥근 끝을 가진 ㄱ자 선. 바깥 가장자리가 칸의 바깥쪽 두 변에 닿는다.
class IntroCornerPainter extends CustomPainter {
  const IntroCornerPainter({
    required this.corner,
    required this.stroke,
    required this.radius,
  });

  final IntroCorner corner;
  final double stroke;
  final double radius; // 바깥 둥글기

  @override
  void paint(Canvas canvas, Size size) {
    final a = size.width;
    final h = stroke / 2;
    final r = radius - h; // 선 가운데 기준 둥글기
    // 왼쪽 위 조각을 그리고, 나머지는 뒤집어서 그린다.
    final flipX =
        corner == IntroCorner.topRight || corner == IntroCorner.bottomRight;
    final flipY =
        corner == IntroCorner.bottomLeft || corner == IntroCorner.bottomRight;
    canvas.translate(flipX ? a : 0, flipY ? a : 0);
    canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
    final path = Path()
      ..moveTo(h, a - h)
      ..lineTo(h, h + r)
      ..arcToPoint(Offset(h + r, h), radius: Radius.circular(r))
      ..lineTo(a - h, h);
    canvas.drawPath(
      path,
      Paint()
        ..color = IntroColors.frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(IntroCornerPainter old) =>
      old.stroke != stroke || old.radius != radius || old.corner != corner;
}

/// 차콜 바탕. [radius]만큼 가운데에 원 구멍이 뚫려 아래 화면이 보인다.
class _HolePainter extends CustomPainter {
  const _HolePainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (radius > 0) {
      path.addOval(
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      );
    }
    canvas.drawPath(path, Paint()..color = IntroColors.background);
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.radius != radius;
}
