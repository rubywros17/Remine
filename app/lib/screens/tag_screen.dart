import 'dart:math';

import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/interest.dart';
import '../models/screenshot_item.dart';
import '../widgets/capture_grid.dart';
import '../widgets/small_widgets.dart';
import 'detail_screen.dart';

/// 태그 모아보기: 그 태그가 붙은 캡처 전부를 카테고리와 상관없이 최신순으로.
/// 관심사 카드·상세의 "같은 관심사"·관심사 알림에서 들어온다.
///
/// 관심사 카드의 횟수는 최근 [windowDays]일 기준이라, 오른쪽 위 큰 숫자도 최근 장수이고
/// 제목 아래에 "최근 2주 15장 · 전체 40장 · 3일 전 마지막"과 날짜별 막대([windowDays]칸)를 같이 보여 준다.
/// 그리드도 "최근 2주"와 "그 전"으로 나눈다. 상세의 좌우 넘기기는 이 목록(최근 → 그 전) 안에서만 돈다.
class TagScreen extends StatefulWidget {
  const TagScreen({
    super.key,
    required this.tag,
    this.windowDays = 14,
    this.random,
  });

  /// '#' 없는 태그 이름.
  final String tag;

  /// 관심사 집계 기간(서버 `windowDays`). 관심사 카드에서 들어오면 그 값, 아니면 서버 기본값과 같은 14.
  final int windowDays;

  /// 해석 문장 고르기용. 테스트에서 시드를 넣어 결정적으로 만든다.
  final Random? random;

  @override
  State<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends State<TagScreen> {
  // ponytail: 최신 100장까지만 받는다(서버 size 상한). 넘으면 "그 전" 구역에 페이지 나누기.
  // 최근 장수·날짜별 막대도 이 목록에서 세므로, 한 태그를 기간 안에 100장 넘게 찍으면 모자라게 나온다.
  // 정확히 하려면 서버 목록 응답에 일자별 개수를 같이 내려 준다.
  static const _pageSize = 100;

  /// 태그별로 마지막에 보여 준 해석 문장. 다시 들어오면 가능하면 다른 문장을 고른다(앱 실행 중 메모리만).
  static final _lastInsight = <String, String>{};

  // 해석 문장은 화면에 들어올 때 한 번 정한다: 리빌드·새로고침에도 같은 문장.
  late final int _pick;
  String? _avoidInsight;

  int _seenRevision = -1;
  int _loadSeq = 0;
  bool _loaded = false;
  List<ScreenshotItem> _items = const [];
  int _total = 0;
  int _recentCount = 0;
  DateTime _today = DateTime(0);

  final Map<int, GlobalKey> _tileKeys = {};
  List<int> _openSnapshot = const [];

  @override
  void initState() {
    super.initState();
    _pick = (widget.random ?? Random()).nextInt(1 << 30);
    _avoidInsight = _lastInsight[widget.tag];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RemineScope.of(context);
    if (_seenRevision != store.revision) {
      _seenRevision = store.revision;
      _load(store);
    }
  }

  Future<void> _load(RemineStore store) async {
    final seq = ++_loadSeq;
    final page = await store.repository.list(tag: widget.tag, size: _pageSize);
    if (!mounted || seq != _loadSeq) return;
    // 서버 관심사 집계와 같은 기준: 지금부터 windowDays일 전 이후에 찍은 캡처. 목록이 최신순이라 앞쪽이 최근이다.
    final since = store.now().subtract(Duration(days: widget.windowDays));
    setState(() {
      _items = page.items;
      _total = page.totalElements;
      _recentCount = page.items.where((s) => !s.takenAt.isBefore(since)).length;
      _today = store.now();
      _loaded = true;
    });
  }

  void _openDetail(int index) {
    _openSnapshot = _items.map((s) => s.id).toList();
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => DetailScreen(
          items: List.of(_items),
          initialIndex: index,
          onViewing: _reveal,
        ),
      ),
    );
  }

  /// 상세에서 보고 있는 캡처의 타일이 보이게(Hero가 돌아올 자리). 빠졌으면 가장 가까운 이웃으로.
  void _reveal(int id) {
    final order = _openSnapshot;
    final start = order.indexOf(id);
    if (start < 0) return;
    for (var d = 0; d < order.length; d++) {
      for (final i in {start + d, start - d}) {
        if (i < 0 || i >= order.length) continue;
        final ctx = _tileKeys[order[i]]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: Duration.zero,
          );
          return;
        }
      }
    }
  }

  GlobalKey _keyFor(int id) => _tileKeys.putIfAbsent(id, GlobalKey.new);

  List<int> get _counts => dailyCounts(_items, _today, widget.windowDays);

  @override
  Widget build(BuildContext context) {
    final window = windowLabel(widget.windowDays);
    final recent = _items.take(_recentCount).toList();
    final older = _items.skip(_recentCount).toList();
    final insight = _loaded
        ? tagInsight(
            widget.tag,
            _counts,
            _today,
            lastCapture: _items.firstOrNull?.takenAt,
            pick: _pick,
            avoid: _avoidInsight,
          )
        : null;
    if (insight != null) _lastInsight[widget.tag] = insight;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.s8,
            AppSpacing.screenPadding,
            AppSpacing.s32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BackButtonCircle(),
              ),
              const SizedBox(height: AppSpacing.s8),
              // 제목과 최근 장수. 화면 리더가 "#뜨개질 최근 2주 4장"으로 한 번에 읽게 묶는다(카테고리 화면과 같은 모양).
              Semantics(
                header: true,
                label: _loaded
                    ? '#${widget.tag} 최근 $window $_recentCount장'
                    : '#${widget.tag}',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: HighlighterText(
                        before: '',
                        highlight: '#${widget.tag}',
                        style: AppText.title,
                      ),
                    ),
                    if (_loaded)
                      // 바탕 위 큰 숫자는 딥 셀라돈(대비 3.70:1). 일반 셀라돈은 1.90:1이라 쓰지 않는다.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$_recentCount',
                          style: AppText.numHero(color: AppColors.celadonDeep),
                        ),
                      ),
                  ],
                ),
              ),
              if (_loaded) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  [
                    '최근 $window $_recentCount장',
                    '전체 $_total장',
                    if (_items.isNotEmpty)
                      lastSeenLabel(_items.first.takenAt, _today),
                  ].join(' · '),
                  style: AppText.caption.copyWith(color: AppColors.inkSub),
                ),
                // 결론(해석 문장) → 근거(막대) 순서
                if (insight != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(insight, style: AppText.body),
                ],
                const SizedBox(height: AppSpacing.s16),
                DailyBars(counts: _counts, today: _today),
              ],
              const SizedBox(height: AppSpacing.s20),
              if (_loaded && _items.isEmpty)
                CaptureGrid(
                  items: const [],
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                ),
              if (recent.isNotEmpty) ...[
                _SectionTitle('최근 $window'),
                CaptureGrid(
                  items: recent,
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                ),
              ],
              if (older.isNotEmpty) ...[
                if (recent.isNotEmpty) const SizedBox(height: AppSpacing.s16),
                const _SectionTitle('그 전'),
                CaptureGrid(
                  items: older,
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                  indexOffset: recent.length,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 두 시각 사이의 달력 날짜 차이(시각은 무시). UTC로 세서 일광절약시간이 있는 시간대에서도 하루가 23시간이 되지 않는다.
int _calendarDays(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// "오늘 마지막"·"어제 마지막"·"N일 전 마지막" (홈 관심사 카드와 같은 문구).
String lastSeenLabel(DateTime last, DateTime now) =>
    switch (_calendarDays(last, now)) {
      <= 0 => '오늘 마지막',
      1 => '어제 마지막',
      final d => '$d일 전 마지막',
    };

/// 오늘을 마지막 칸으로 하는 [days]일치 날짜별 캡처 수. 0번 칸이 가장 오래된 날.
List<int> dailyCounts(List<ScreenshotItem> items, DateTime now, int days) {
  final counts = List.filled(days, 0);
  for (final s in items) {
    final i = days - 1 - _calendarDays(s.takenAt, now);
    if (i >= 0 && i < days) counts[i]++;
  }
  return counts;
}

/// 해석 문장 문구. 상황마다 2~3개이고 [tagInsight]가 그중 하나를 고른다.
/// 자리표시: {tag} 태그 이름, {m}·{d} 날짜, {x} 마지막 캡처 후 일수, {n} 장수·일수, {window} 기간("2주").
/// 표기는 "캡처"("캡쳐"·"찍었어요" 쓰지 않음).
const insightPhrases = {
  'dormant': ['마지막 캡처가 {x}일 전이에요. 다시 꺼내 볼까요?', '{window} 넘게 소식이 없어요. 아직 좋아하죠?'],
  'quiet': [
    '{m}월 {d}일엔 푹 빠져 있었는데, 요즘 {x}일째 조용하네요',
    '한창일 땐 하루 {n}장씩 캡처했는데, 잊고 있었나요?',
    '{x}일째 소식이 없어요. 아직 관심 있죠?',
  ],
  'pause': ['요즘 {x}일째 조용하네요', '잠깐 쉬어가는 중이네요'],
  'new': ['오, 새로운 관심사가 생겼네요!', '요즘 여기에 꽂혔군요. 앞으로가 기대돼요'],
  'rising': [
    '요즘 다시 빠지는 중이에요',
    '잊은 줄 알았는데, 다시 돌아왔네요!',
    '최근 며칠 새 {n}장이나 모았어요. 진심이네요!',
  ],
  'burst': [
    '{m}월 {d}일 하루에 {n}장을 몰아서 캡처했어요',
    '{m}월 {d}일, 무슨 일 있었어요? 하루에 {n}장이나!',
  ],
  'today': ['오늘도 캡처했어요. 한창 빠져 있는 중!', '오늘의 관심사도 #{tag}'],
  'steady': ['{window} 동안 꾸준히 모았어요', '{window} 중 {n}일이나 캡처했어요. 진심이네요'],
};

/// 날짜별 막대([counts], 오늘이 마지막 칸) 위 해석 문장. [lastCapture]는 기간과 상관없이 가장 최근 캡처 시각이고,
/// 그것도 없으면 null.
/// 상황은 마지막 캡처로부터 지난 날짜로 먼저 나눈다: 오래 잠잠(기간 안 0장 = 2주 이상) → 잠잠(7일 이상, 카드와 같은 기준)
/// → 쉬는 중(3일 이상). 그보다 최근이면 새로 생김(최근 3일에만 있음)
/// → 다시 늘어남(최근 3일 > 그 전 4일, 그보다 앞에도 있었음) → 몰아서(하루가 전체의 절반 이상)
/// → 오늘 캡처함 → 그 외.
/// 문구는 그 상황의 문구 중 [pick]번째(나머지 연산)이고, [avoid]와 같은 문장은 다른 문구가 있으면 뺀다.
String? tagInsight(
  String tag,
  List<int> counts,
  DateTime today, {
  DateTime? lastCapture,
  int pick = 0,
  String? avoid,
}) {
  final total = counts.fold(0, (a, b) => a + b);
  if (total == 0 && lastCapture == null) return null;
  int sum(int from, int to) => counts
      .sublist(from.clamp(0, counts.length), to.clamp(0, counts.length))
      .fold(0, (a, b) => a + b);
  final last = counts.length;
  // 가장 많은 날(같으면 최근 날)
  var peak = 0;
  for (var i = 0; i < last; i++) {
    if (counts[i] >= counts[peak]) peak = i;
  }
  final peakDay = today.subtract(Duration(days: last - 1 - peak));
  final recent3 = sum(last - 3, last);
  final sinceLast = total == 0
      ? _calendarDays(lastCapture!, today)
      : last - 1 - counts.lastIndexWhere((c) => c > 0);

  final (key, n) = switch (()) {
    _ when total == 0 => ('dormant', 0),
    // 카드의 "잊은 관심사"와 같은 기준
    _ when sinceLast >= Interest.forgottenAfterDays => ('quiet', counts[peak]),
    _ when recent3 == 0 => ('pause', 0),
    _ when recent3 == total => ('new', recent3),
    _ when recent3 > sum(last - 7, last - 3) && sum(0, last - 7) > 0 => (
      'rising',
      recent3,
    ),
    // 하루 1장은 "몰아서"라 부르기 어색해서 2장 이상일 때만
    _ when counts[peak] >= 2 && counts[peak] * 2 >= total => (
      'burst',
      counts[peak],
    ),
    _ when counts.last > 0 => ('today', 0),
    _ => ('steady', counts.where((c) => c > 0).length),
  };
  final lines = [
    for (final p in insightPhrases[key]!)
      p
          .replaceAll('{tag}', tag)
          .replaceAll('{m}', '${peakDay.month}')
          .replaceAll('{d}', '${peakDay.day}')
          .replaceAll('{x}', '$sinceLast')
          .replaceAll('{n}', '$n')
          .replaceAll('{window}', windowLabel(last)),
  ];
  if (lines.length > 1) lines.remove(avoid);
  return lines[pick % lines.length];
}

/// 날짜별 캡처 수 막대. 있는 날은 셀라돈, 0인 날은 테두리색 낮은 막대. 아래 양끝에 시작 날짜와 "오늘".
/// 처음 그려질 때 막대가 아래에서 올라온다("애니메이션 줄이기"면 시간 0이라 바로 다 그려진다).
///
/// [Flutter 메모] TweenAnimationBuilder는 처음 만들어질 때 begin → end로 한 번 움직이고, 값이 같으면 다시 움직이지 않는다.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.counts, required this.today});

  final List<int> counts;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final max = counts.fold(1, (a, b) => b > a ? b : a);
    final activeDays = counts.where((c) => c > 0).length;
    final start = today.subtract(Duration(days: counts.length - 1));
    final caption = AppText.caption.copyWith(
      fontSize: AppTagBars.labelSize,
      color: AppColors.inkSub,
    );
    return Semantics(
      label: '최근 ${counts.length}일 중 $activeDays일 캡처',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.duration(context, MotionDuration.slow),
            curve: AppMotion.standard,
            builder: (context, t, _) => SizedBox(
              height: AppTagBars.height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, c) in counts.indexed) ...[
                    if (i > 0) const SizedBox(width: AppTagBars.gap),
                    Expanded(
                      child: Container(
                        height: c == 0
                            ? AppTagBars.emptyHeight
                            : AppTagBars.height * c / max * t,
                        decoration: BoxDecoration(
                          color: c == 0 ? AppColors.border : AppColors.celadon,
                          borderRadius: BorderRadius.circular(
                            AppTagBars.radius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Expanded(child: Text(formatMonthDay(start), style: caption)),
              Text('오늘', style: caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: Semantics(header: true, child: Text(text, style: AppText.cardTitle)),
  );
}
