import '../core/helpers.dart';
import '../data/device/older_progress.dart';
import '../data/device/settings_store.dart';

/// 예전 스크린샷 정리 화면 문구(범위 고르기 · 기간 시트 · 예전 스크린샷 화면 · 설정 줄 · 관심사 점선 칸)를 한곳에.
/// [Dart 메모] `abstract final class`는 상수만 모아 두는 네임스페이스(tokens.dart와 같은 방식).
abstract final class OlderTexts {
  // ① 범위 고르기
  static const rangeTitle = '어디까지 정리할까요?';
  static String rangeIntroCount(int n) => '총 ${formatThousands(n)}장';
  static const rangeIntroBefore = '앨범 속 스크린샷 ';
  static const rangeIntroAfter = '이 있어요.';
  static const rangeIntroRest = '오래된 것까지 보면 잊고 있던 관심사를\n더 많이 찾을 수 있어요';
  static const recent300 = '최근 300장';
  static const recent300Badge = '오늘 바로';
  static String recentMonths(int m) => '약 $m달 치';
  static String minutes(int m) => '약 $m분';
  static const todayDone = '오늘 끝';
  static const recentDone = '완료';
  static const recentDoneSub = '정리했어요';
  static const year = '최근 1년';
  static const yearBadge = '추천';
  static const all = '전부';
  static String shots(int n) => '${formatThousands(n)}장';
  static String days(int d) => '$d일';

  /// 일수 아래 줄: 언제부터 세는지. 첫 실행은 첫 분석(최신 300장)이 오늘 몫을 쓴다.
  static String startsFrom({required bool firstRun, required int today}) =>
      firstRun
      ? '오늘 최신 300장부터'
      : today > 0
      ? '오늘 ${formatThousands(today)}장부터'
      : '내일부터';
  static const custom = '기간 직접 고르기';
  static String customChosen(DateTime from, int n) =>
      '직접: ${formatYearMonth(from)}부터 · ${formatThousands(n)}장';
  static const noteBold = '300장';
  static const noteBefore = '하루에 ';
  static const noteAfter = '씩 정리해요.\n나머지는 앱을 열 때마다 이어서 분석해요.';
  static const firstNoteBefore = '오늘은 ';
  static const firstNoteBold = '최신 300장';
  static const firstNoteAfter =
      '을 먼저 정리해요.\n나머지는 내일부터 앱을 열 때마다 하루 300장씩 이어서 분석해요.';
  static const start = '정리 시작';
  static const confirm = '이 범위로 정하기';

  // ② 기간 직접 고르기
  static const sheetTitle = '얼마나 거슬러 올라갈까요?';
  static const shotUnit = '장';
  static String sheetFrom(DateTime? from, int days, {required int today}) =>
      '${from == null ? '처음' : formatYearMonth(from)}부터 · '
      '${today > 0 ? '오늘 포함' : '내일부터'} 약 $days일';
  static String tick(int? months) => switch (months) {
    null => '전부',
    12 => '1년',
    _ => '$months달',
  };
  static String sliderLabel(int? months, int n) =>
      '${months == null ? '전부' : '${tick(months)} 전부터'} ${formatThousands(n)}장';

  // ④ 설정 줄
  static const settingsRow = '예전 스크린샷 정리';
  static const settingsBodyBefore = '아직 안 본 스크린샷 ';
  static const settingsBodyRest = ' · 하루 300장씩';
  static const pickRange = '분석 범위를 골라 주세요';

  // ⑤ 예전 스크린샷
  static const shotsTitle = '예전 스크린샷';
  static String progressLine(int seen, int total, DateTime? until) =>
      '${formatThousands(seen)} / ${formatThousands(total)}장'
      '${until == null ? '' : ' · ${formatYearMonth(until)}까지 봤어요'}';
  static const quotaLabel = '오늘 남은 예전 스크린샷 정리 횟수';
  static const quotaAside = '새 스크린샷은 상관없이\n바로 분석해요';
  static const quotaDoneTitle = '오늘 몫은 다 정리했어요';
  static const quotaDoneBody = '내일 앱을 열면 다음 300장을 이어서 정리해요.';
  static String quotaDoneLeft(int n) =>
      '남은 ${formatThousands(n)}장 · 약 ${olderDaysFor(n)}일';
  static const allDone = '예전 스크린샷을 모두 정리했어요';
  static const continueTitle = '이어서 정리하기';
  static const continueBody = '앱을 열 때마다 남은 스크린샷 분석';
  static const wifiOnly = 'Wi-Fi에서만';
  static const chargingOnly = '충전 중일 때만';
  static const rangeRow = '분석 범위';
  static const faster = '더 빨리 정리하기';
  static const fasterBody = '하루 한도 없이 한 번에';
  static const comingSoon = '준비 중';

  // ⑥ 관심사 점선 칸
  static const moreTitle = '더 오래된 관심사도 찾아볼까요?';
  static String moreBody(int n) => '아직 안 본 예전 스크린샷이 ${formatThousands(n)}장 있어요';
  static const moreButton = '예전 스크린샷 정리하기';

  /// 범위 이름("최근 1년", "2026년 2월부터").
  static String rangeName(OlderRangeKind? kind, DateTime? from) =>
      switch (kind) {
        null => '아직 안 골랐어요',
        OlderRangeKind.recent300 => recent300,
        OlderRangeKind.year => year,
        OlderRangeKind.all => all,
        OlderRangeKind.custom =>
          from == null ? all : '${formatYearMonth(from)}부터',
      };
}
