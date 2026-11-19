import 'dart:math' as math;

import 'gallery_reader.dart';
import 'settings_store.dart';

/// 하루에 정리하는 예전 스크린샷 장수(서버 `remine.analyze.daily-older-limit`). 서버 값을 받기 전 표시용.
const olderDailyLimit = 300;

/// 첫 분석(최근 장)에서 보는 장수. [DeviceCaptureService.maxPhotos]와 같다.
const olderRecentShots = 300;

/// [n]장을 하루 [olderDailyLimit]장씩 정리하면 걸리는 날(올림, 0장이면 0).
int olderDaysFor(int n) => (n + olderDailyLimit - 1) ~/ olderDailyLimit;

/// [n]장을 오늘 [today]장, 내일부터 하루 [olderDailyLimit]장씩 정리할 때 걸리는 날.
/// [today]가 0보다 크면 오늘도 하루로 센다. 서버는 첫 분석(최신 300장)도 예전 몫으로 세므로,
/// 첫 실행은 범위 전체를 today = 최신 300장으로 세면 ⌈n/300⌉(오늘 = 첫 분석)과 같다.
int olderDays(int n, {required int today}) {
  if (n <= 0) return 0;
  if (today <= 0) return olderDaysFor(n);
  return 1 + olderDaysFor(math.max(0, n - today));
}

/// 저장된 서버 몫([SettingsStore.olderQuota])으로 본 오늘 남은 예전 장수.
/// 없으면 0(내일부터로 안내), 초기화 시각이 지났으면 하루 한도가 다시 찬 것으로 본다.
int olderTodayLeft(({int remaining, DateTime? resetsAt})? quota, DateTime now) {
  if (quota == null) return 0;
  final resetsAt = quota.resetsAt;
  if (resetsAt != null && !resetsAt.isAfter(now)) return olderDailyLimit;
  return math.max(0, quota.remaining);
}

/// [now]에서 [months]달 전 같은 날.
DateTime monthsAgo(DateTime now, int months) =>
    DateTime(now.year, now.month - months, now.day);

/// 예전 스크린샷 정리 현황(설정 줄·예전 스크린샷 화면·관심사 점선 칸이 같이 쓴다). 장수는 갤러리 count라 빠르다.
class OlderOverview {
  const OlderOverview({
    required this.kind,
    required this.from,
    required this.all,
    required this.total,
    required this.unseen,
    this.seenUntil,
  });

  /// 고른 범위. null이면 아직 안 골랐다.
  final OlderRangeKind? kind;
  final DateTime? from;

  /// 스크린샷 앨범 전체 장수.
  final int all;

  /// 고른 범위 안의 장수("n / 전체장"의 전체).
  final int total;

  /// 아직 안 본 예전 스크린샷. "최근 300장"이거나 아직 안 골랐으면 범위를 넓혔을 때 볼 수 있는 장수(점선 칸 입구용).
  final int unseen;

  /// 어디까지 봤는지(커서 시각). 아직 예전 스크린샷을 하나도 안 봤으면 null.
  final DateTime? seenUntil;

  bool get chosen => kind != null;

  /// 예전 스크린샷을 정리하는 범위인지("최근 300장"·안 고름이면 false).
  bool get scanning =>
      kind != null && kind != OlderRangeKind.recent300 && total > 0;

  int get seen => math.max(0, total - (scanning ? unseen : 0));

  /// 진행률 0~1.
  double get progress => total == 0 ? 1 : (seen / total).clamp(0.0, 1.0);

  bool get done => scanning && unseen == 0;
}

/// Screenshots 앨범 id. 없으면 null.
Future<String?> screenshotsAlbum(GalleryReader reader) async {
  for (final a in await reader.albums()) {
    if (a.isScreenshots) return a.id;
  }
  return null;
}

/// 저장된 범위·커서로 현황을 센다. 앨범이 없으면 null.
Future<OlderOverview?> loadOlderOverview(
  GalleryReader reader,
  SettingsStore settings,
) async {
  final album = await screenshotsAlbum(reader);
  if (album == null) return null;
  final all = await reader.count(album);
  final value = await settings.olderRangeFrom();
  final kind = await settings.olderRangeKind() ?? _kindOf(value);
  final range = olderRangeStart(value);
  if (!range.enabled) {
    // 안 고름·최근 300장: 예전 스크린샷은 안 본다. 남은 것 = 최근 300장 뒤 전부
    return OlderOverview(
      kind: kind,
      from: null,
      all: all,
      total: math.min(olderRecentShots, all),
      unseen: math.max(0, all - olderRecentShots),
    );
  }
  final from = range.from;
  final total = await reader.count(album, from: from);
  final cursor = PhotoPosition.decode(await settings.olderCursor());
  final int unseen;
  if (cursor == null) {
    unseen = math.max(0, total - olderRecentShots);
  } else if (from != null && cursor.time.isBefore(from)) {
    unseen = 0; // 범위를 줄여 이미 다 봤다
  } else {
    unseen = await reader.count(album, from: from, before: cursor.time);
  }
  return OlderOverview(
    kind: kind,
    from: from,
    all: all,
    total: total,
    unseen: unseen,
    seenUntil: cursor?.time,
  );
}

/// 범위 종류를 따로 저장하기 전 값(디버그 등)이면 값에서 짐작한다.
OlderRangeKind? _kindOf(String? value) => switch (value) {
  null || '' => null,
  olderRangeNone => OlderRangeKind.recent300,
  olderRangeAll => OlderRangeKind.all,
  _ => OlderRangeKind.custom,
};

/// 범위 고르기 화면에 보일 장수.
class OlderRangeCounts {
  const OlderRangeCounts({
    required this.all,
    required this.recentMonths,
    required this.byMonths,
  });

  final int all;

  /// 최근 300장이 몇 달 치인지(약).
  final int recentMonths;

  /// [olderSliderMonths]의 달 수 → 그 기간 장수. 전부는 [all].
  final Map<int, int> byMonths;

  int get year => byMonths[12] ?? all;
}

/// 기간 직접 고르기 슬라이더 눈금(달). 마지막 "전부"는 null.
const olderSliderMonths = <int?>[1, 3, 6, 9, 12, null];

/// 앨범이 없으면 null.
Future<OlderRangeCounts?> loadOlderRangeCounts(
  GalleryReader reader,
  DateTime now,
) async {
  final album = await screenshotsAlbum(reader);
  if (album == null) return null;
  final all = await reader.count(album);
  final byMonths = <int, int>{};
  for (final m in olderSliderMonths.whereType<int>()) {
    byMonths[m] = await reader.count(album, from: monthsAgo(now, m));
  }
  // 최근 300장이 들어가는 가장 짧은 달 수. ponytail: 한 달씩 늘려 센다(대개 몇 번), 20년에서 멈춘다.
  final target = math.min(olderRecentShots, all);
  var months = 1;
  while (months < 240 &&
      (byMonths[months] ??
              await reader.count(album, from: monthsAgo(now, months))) <
          target) {
    months++;
  }
  return OlderRangeCounts(all: all, recentMonths: months, byMonths: byMonths);
}
