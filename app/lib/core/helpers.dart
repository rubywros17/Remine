import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/category.dart';
import 'tokens.dart';

/// 카테고리별 아이콘 (docs/design.md 6장).
IconData categoryIcon(Category category) => switch (category) {
  Category.shopping => LucideIcons.shoppingBag,
  Category.entertainment => LucideIcons.ticket,
  Category.place => LucideIcons.mapPin,
  Category.info => LucideIcons.lightbulb,
  Category.chat => LucideIcons.messageSquare,
  Category.schedule => LucideIcons.calendar,
  Category.etc => LucideIcons.ellipsis,
};

String _two(int n) => n.toString().padLeft(2, '0');

/// "10.19"
String formatMonthDay(DateTime d) => '${_two(d.month)}.${_two(d.day)}';

/// "MON 10.19"
String formatWeekdayDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${formatMonthDay(d)}';

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// 출처 칩 표기: 대문자, 자주 나오는 붙여 쓴 앱 이름만 띄어 쓴다(공백·대소문자 무관하게 비교). 사전에 없으면 대문자 그대로.
String sourceAppLabel(String name) {
  final upper = name.trim().toUpperCase();
  return _sourceAppSpacing[upper.replaceAll(' ', '')] ?? upper;
}

const _sourceAppSpacing = {
  'KAKAOMAP': 'KAKAO MAP',
  'NAVERMAP': 'NAVER MAP',
  'NMAP': 'NAVER MAP',
  'GOOGLEMAPS': 'GOOGLE MAPS',
  'KAKAOTALK': 'KAKAO TALK',
  'KAKAOPAGE': 'KAKAO PAGE',
  'NAVERWEBTOON': 'NAVER WEBTOON',
  'YOUTUBEMUSIC': 'YOUTUBE MUSIC',
};

/// "2026.11.06 (TUE)  |  13:58" — 캡처 상세의 촬영 시각(24시간제, 구분선 앞뒤 공백 2칸).
String formatStamp(DateTime d) =>
    '${d.year}.${formatMonthDay(d)} (${_weekdays[d.weekday - 1]})'
    '  |  ${_two(d.hour)}:${_two(d.minute)}';

/// 화면 전환 라우트: 페이드. 시간은 모션 토큰이고, "애니메이션 줄이기"면 0이라 즉시 바뀐다.
///
/// [Dart/Flutter 메모] Route는 Navigator가 쌓는 화면 한 장이다. Hero 전환은 PageRoute에서만 동작한다.
Route<T> appRoute<T>(BuildContext context, WidgetBuilder builder) {
  final duration = AppMotion.duration(context, MotionDuration.slow);
  return PageRouteBuilder<T>(
    // 전환이 끝나면 아래 화면을 그리지 않는다(opaque).
    opaque: true,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppMotion.emphasized,
            reverseCurve: AppMotion.exit,
          ),
          child: child,
        ),
  );
}

/// 목록 → 태그·카테고리 화면 전환: 페이드 스루. 나가는 화면이 0~225ms에 빠지고, 들어오는 화면이 180ms부터 들어온다.
/// "애니메이션 줄이기"면 시간 0이라 즉시 바뀐다.
///
/// [Flutter 메모] `delegatedTransition`은 이 라우트가 올라오거나 내려갈 때 **아래 화면(목록)**에
/// 씌울 전환이다. 그때 `secondaryAnimation`이 이 라우트의 진행값(0→1, 돌아올 땐 1→0)이다.
///
/// [heroes]가 false면 이 전환(들어갈 때·돌아올 때)에서만 Hero가 날지 않는다. 다 들어온 뒤
/// 이 화면에서 상세로 가는 Hero는 그대로 난다.
/// [Flutter 메모] Hero는 두 화면에 같은 tag가 있으면 전환 동안 위층에서 날아간다. `HeroMode(enabled: false)`
/// 아래의 Hero는 짝을 찾을 때 빠진다.
Route<T> fadeThroughRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool heroes = true,
}) {
  final reduced = AppMotion.reduced(context);
  return _FadeThroughRoute<T>(
    builder: builder,
    forward: reduced ? Duration.zero : AppMotion.fadeThroughForward,
    reverse: reduced ? Duration.zero : AppMotion.fadeThroughReverse,
    heroes: heroes,
  );
}

class _FadeThroughRoute<T> extends PageRouteBuilder<T> {
  _FadeThroughRoute({
    required WidgetBuilder builder,
    required Duration forward,
    required Duration reverse,
    required this.heroes,
  }) : super(
         opaque: true,
         transitionDuration: forward,
         reverseTransitionDuration: reverse,
         pageBuilder: (context, _, _) => builder(context),
         transitionsBuilder: (context, animation, _, child) => AnimatedBuilder(
           animation: animation,
           builder: (context, child) {
             final (opacity, scale) = _fadeThrough(animation, incoming: true);
             return _faded(opacity, scale, child!);
           },
           child: child,
         ),
       );

  final bool heroes;

  /// Hero는 페이지 본문 안에서만 찾으니 HeroMode도 본문 안에 둔다. `animation` 대신 [controller]를 보는 이유:
  /// 들어갈 때 HeroController가 위치를 재는 한 프레임 동안 라우트를 offstage로 두면서 `animation`을
  /// 완료(1)로 바꿔 끼우기 때문이다. controller는 실제 진행 상태 그대로다.
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final page = super.buildPage(context, animation, secondaryAnimation);
    return heroes
        ? page
        : _HeroesWhenSettled(animation: controller!, child: page);
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) =>
          // 목록이 빠진 자리에 검은 창이 보이지 않게 바탕색을 깐다(목록 라우트가 맨 아래라 여기가 배경).
          ColoredBox(
            color: AppColors.background,
            child: AnimatedBuilder(
              animation: secondaryAnimation,
              builder: (context, child) {
                final (opacity, scale) = _fadeThrough(
                  secondaryAnimation,
                  incoming: false,
                );
                return _faded(opacity, scale, child!);
              },
              child: child,
            ),
          );
}

/// [animation]이 다 들어온 상태(completed)일 때만 Hero를 켠다.
///
/// [Flutter 메모] HeroController는 pop 직후 **다음 프레임 끝**에 Hero 짝을 찾는다. 진행값은 그 프레임엔
/// 아직 1이라 값만 보면 늦고, 상태(reverse)가 바뀌는 순간 setState로 다시 그려야 그 프레임에 꺼져 있다.
class _HeroesWhenSettled extends StatefulWidget {
  const _HeroesWhenSettled({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_HeroesWhenSettled> createState() => _HeroesWhenSettledState();
}

class _HeroesWhenSettledState extends State<_HeroesWhenSettled> {
  void _onStatus(AnimationStatus _) => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_HeroesWhenSettled old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HeroMode(enabled: widget.animation.isCompleted, child: widget.child);
}

Widget _faded(double opacity, double scale, Widget child) => Opacity(
  opacity: opacity,
  child: Transform.scale(scale: scale, child: child),
);

/// 페이드 스루 한 순간의 (투명도, 크기). [a]는 태그 라우트의 진행값이고, 돌아올 때(reverse)는
/// 1→0으로 줄어드니 경과 시간으로 바꿔 계산한다. [incoming]이면 태그 화면, 아니면 목록.
(double, double) _fadeThrough(Animation<double> a, {required bool incoming}) {
  const outMs = AppMotion.fadeThroughOutMs;
  const inStart = AppMotion.fadeThroughInStartMs;
  double phase(double ms, int start, int length) =>
      ((ms - start) / length).clamp(0.0, 1.0);

  if (a.status == AnimationStatus.reverse) {
    final ms = (1 - a.value) * AppMotion.fadeThroughReverse.inMilliseconds;
    if (incoming) {
      final t = AppMotion.fadeThroughOut.transform(phase(ms, 0, outMs));
      return (1 - t, 1 + (AppMotion.fadeThroughTagOutScale - 1) * t);
    }
    final t = AppMotion.fadeThroughIn.transform(
      phase(ms, inStart, AppMotion.fadeThroughReverseInMs),
    );
    return (
      t,
      AppMotion.fadeThroughListScale + (1 - AppMotion.fadeThroughListScale) * t,
    );
  }
  final ms = a.value * AppMotion.fadeThroughForward.inMilliseconds;
  if (incoming) {
    final t = AppMotion.fadeThroughIn.transform(
      phase(ms, inStart, AppMotion.fadeThroughForwardInMs),
    );
    return (
      t,
      AppMotion.fadeThroughTagInScale -
          (AppMotion.fadeThroughTagInScale - 1) * t,
    );
  }
  final t = AppMotion.fadeThroughOut.transform(phase(ms, 0, outMs));
  return (1 - t, 1 - (1 - AppMotion.fadeThroughListScale) * t);
}

/// 집계 기간 이름: 7의 배수면 "2주", 아니면 "10일".
String windowLabel(int days) => days % 7 == 0 ? '${days ~/ 7}주' : '$days일';

/// 마지막 글자의 받침 번호. 0이면 받침 없음(한글이 아니어도 0), 8이면 ㄹ.
/// [한글 메모] 완성형 한글은 0xAC00부터 (초성×21 + 중성)×28 + 종성 순서라 28로 나눈 나머지가 받침이다.
int _finalConsonant(String word) {
  if (word.isEmpty) return 0;
  final code = word.runes.last - 0xAC00;
  return code >= 0 && code <= 11171 ? code % 28 : 0;
}

/// "쇼핑이에요", "정보예요": 받침이 있으면 "이에요".
String copulaFor(String word) => _finalConsonant(word) != 0 ? '이에요' : '예요';

/// "쇼핑으로", "정보로", "문화생활로": 받침이 있으면 "으로", 없거나 ㄹ받침이면 "로".
String withRo(String word) {
  final c = _finalConsonant(word);
  return '$word${c != 0 && c != 8 ? '으로' : '로'}';
}
