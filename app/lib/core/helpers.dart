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
