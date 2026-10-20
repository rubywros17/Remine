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
String formatWeekdayDate(DateTime d) {
  const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return '${days[d.weekday - 1]} ${formatMonthDay(d)}';
}

/// "10.19 14:14"
String formatStamp(DateTime d) =>
    '${formatMonthDay(d)} ${_two(d.hour)}:${_two(d.minute)}';

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
