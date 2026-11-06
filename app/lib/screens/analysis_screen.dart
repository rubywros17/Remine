import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../data/remote/sync_status.dart';
import '../models/category.dart';
import '../widgets/app_button.dart';
import '../widgets/drawer_stage.dart';
import '../widgets/small_widgets.dart';

/// 첫 분석 화면. [status]가 있으면 실제 동기화 진행(장수·남은 예상 시간·카드가 날아드는 서랍 칸)을 보여 주고,
/// 없으면(개발용 `START_SCREEN=analysis`, 테스트) 가짜 진행값을 보여 준다.
///
/// - 진행 중: [onHome]이 있으면 "홈에서 먼저 볼래요"로 분석 중에도 홈에 나갈 수 있다(분석은 계속된다).
/// - 끝나면: 자동으로 넘어가지 않고 "N장 정리했어요" 요약과 [홈에서 둘러보기] 버튼을 보여 준다.
/// - 큰 숫자는 서버 진행 수가 아니라 칸 합계다. 완료 상태도 칸을 다 채운 뒤에 보여 준다([DrawerStage.onProgress]).
///
/// 레이아웃: 상단 숫자와 하단 버튼 사이의 남는 높이를 [DrawerStage]가 쓴다. 그래도 모자라면 내용 전체가 함께 스크롤된다.
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({
    super.key,
    this.done = 128,
    this.total = 300,
    this.status,
    this.onHome,
  });

  final int done;
  final int total;
  final SyncStatus? status;
  final VoidCallback? onHome;

  // 가짜 진행값: 지금까지 꺼낸 128장의 카테고리별 개수 (합계 128).
  static const _counts = {
    Category.shopping: 31,
    Category.info: 28,
    Category.place: 17,
    Category.entertainment: 11,
    Category.chat: 14,
    Category.schedule: 6,
    Category.etc: 21,
  };

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return _Body(done: done, total: total, counts: _counts, onHome: onHome);
    }
    // 다른 실행의 상태가 들어오면 큐·비행 중인 카드를 이어받지 않고 새로 시작한다.
    return _LiveAnalysis(
      key: ObjectKey(status),
      status: status,
      onHome: onHome,
    );
  }
}

class _LiveAnalysis extends StatefulWidget {
  const _LiveAnalysis({super.key, required this.status, this.onHome});

  final SyncStatus status;
  final VoidCallback? onHome;

  @override
  State<_LiveAnalysis> createState() => _LiveAnalysisState();
}

class _LiveAnalysisState extends State<_LiveAnalysis> {
  late int _landed = widget.status.counts.values.fold(0, (a, b) => a + b);
  late bool _settled = widget.status.finished;

  /// 완료 요약에 쓰는 전체 개수(홈 막대와 같은 데이터). 불러오기 전에는 null이라 요약을 그리지 않는다.
  Map<Category, int>? _totals;
  bool _totalsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) _loadTotals();
  }

  void _onProgress(int landed, bool settled) {
    if (landed == _landed && settled == _settled) return;
    setState(() {
      _landed = landed;
      _settled = settled;
    });
    if (settled) _loadTotals();
  }

  /// 칸을 다 채운 뒤 한 번. 이번 실행 개수가 아니라 저장소 요약(휴지통 제외, 기기 분류 포함)이다.
  /// 저장소가 없는 화면(개발용·테스트)은 이번 실행 개수로 대신한다.
  Future<void> _loadTotals() async {
    if (_totalsRequested) return;
    _totalsRequested = true;
    final store = RemineScope.maybeOf(context);
    final totals = store == null
        ? widget.status.counts
        : {
            for (final c in (await store.repository.summary()).categories)
              c.category: c.count,
          };
    if (mounted) setState(() => _totals = totals);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    // [Flutter 메모] ListenableBuilder는 ChangeNotifier가 알릴 때마다 builder만 다시 실행한다.
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final eta = status.eta;
        return _Body(
          done: _landed,
          total: status.total,
          counts: status.counts,
          status: status,
          onProgress: _onProgress,
          finished: _settled,
          summaryCounts: _totals,
          etaText: eta != null
              ? formatEta(eta)
              : status.running
              ? etaPendingText
              : null,
          progressText: status.progressMessage,
          issueText: _settled ? status.bannerMessage : null,
          onHome: widget.onHome,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.done,
    required this.total,
    required this.counts,
    this.status,
    this.onProgress,
    this.finished = false,
    this.summaryCounts,
    this.etaText,
    this.progressText,
    this.issueText,
    this.onHome,
  });

  final int done;
  final int total;
  final Map<Category, int> counts;

  /// 없으면(개발용 가짜 진행값) 칸은 [counts]로 멈춰 있고 카드가 날지 않는다.
  final SyncStatus? status;
  final void Function(int landed, bool settled)? onProgress;
  final bool finished;

  /// 완료 요약의 카테고리별 개수(전체 기준).
  final Map<Category, int>? summaryCounts;
  final String? etaText;
  final String? progressText;
  final String? issueText;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGray,
      body: SafeArea(
        // 남는 높이는 가운데 스테이지가 쓰고, 모자라면 함께 스크롤된다.
        // [Flutter 메모] 스크롤 안의 Column은 높이가 무한이라 Expanded를 못 쓴다. "최소 높이 = 화면 높이"로 두고
        // IntrinsicHeight로 내용 높이를 정해 주면 Expanded가 남는 높이를 받는다.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.s16,
                    AppSpacing.screenPadding,
                    AppSpacing.s16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BrandHeader(
                            pillText: finished ? 'DONE' : 'DIGGING…',
                            color: AppColors.white,
                          ),
                          const SizedBox(height: AppSpacing.s32),
                          _Counter(
                            done: done,
                            total: total,
                            finished: finished,
                            etaText: etaText,
                            issueText: issueText,
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          if (finished)
                            AnalysisSummary(counts: summaryCounts ?? const {})
                          else ...[
                            _ProgressSlot(
                              text: progressText,
                              working: status != null,
                            ),
                            const SizedBox(height: AppSpacing.s12),
                            _FixedLine(
                              keepScreenOnHint,
                              style: AppText.caption.copyWith(
                                color: AppColors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Expanded(
                        child: DrawerStage(
                          status: status,
                          counts: counts,
                          onProgress: onProgress,
                          finished: finished,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (onHome != null) ...[
                            if (finished)
                              AppButton(label: '홈에서 둘러보기', onTap: onHome)
                            else
                              Center(
                                child: AppButton(
                                  label: '홈에서 먼저 볼래요',
                                  onTap: onHome,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.s16),
                          ],
                          const PrivacyNote(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 큰 진행 숫자. 진행 중에는 "N / M장 꺼냈어요", 끝나면 "N장 정리했어요"와 빠진 장수.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.done,
    required this.total,
    required this.finished,
    required this.etaText,
    this.issueText,
  });

  final String? issueText;
  final int done;
  final int total;
  final bool finished;
  final String? etaText;

  /// 끝났는데 꺼낸 게 없을 때(새 캡처 없음·서버에 닿지 못함).
  static const _noneText = '새로 꺼낼 캡처가 없어요';

  String get _finishedText => done == 0 ? _noneText : '$done장 정리했어요';

  /// 칸에 들어가지 못한 장수(서버가 이미 가진 캡처, 다음에 다시 보낼 캡처 등).
  int get _left => total - done;

  @override
  Widget build(BuildContext context) {
    // 큰 진행 숫자: 셀라돈 on 다크그레이 (대비 4.43:1)
    return Semantics(
      label: finished ? _finishedText : '$total장 중 $done장 꺼냈어요',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$done',
              style: AppText.numHero(color: AppColors.celadon, size: 128),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            finished
                ? (done == 0 ? _finishedText : '장 정리했어요')
                : '/ $total장 꺼냈어요',
            style: AppText.sectionTitle.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (!finished)
            _FixedLine(
              etaText,
              style: AppText.body.copyWith(color: AppColors.celadonSoft),
            )
          else if (issueText != null)
            Text(
              issueText!,
              style: AppText.caption.copyWith(color: AppColors.lemon),
            )
          else if (_left > 0 && done > 0)
            Text(
              leftOutText(total, _left),
              style: AppText.caption.copyWith(
                color: AppColors.white.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
    );
  }
}

/// 첫 묶음이 끝나기 전 남은 시간 자리. 믿을 값이 없어 숫자를 보여 주지 않는다.
const etaPendingText = '남은 시간 계산 중이에요';

/// 칸에 들어가지 못한 장 안내. 서버가 이미 분석한 캡처(건너뜀)와 다음 실행에 다시 보낼 캡처(실패·마감)를 한 문장으로 묶는다.
String leftOutText(int total, int left) =>
    '$total장 중 $left장은 이미 정리했거나 다음에 다시 확인해요';

/// 많은 순서로 상위 [limit]개(0장 제외). 동점이면 칸 순서상 앞의 것.
List<MapEntry<Category, int>> topCategories(
  Map<Category, int> counts, {
  int limit = 3,
}) {
  final list = [
    for (final c in Category.values)
      if ((counts[c] ?? 0) > 0) MapEntry(c, counts[c]!),
  ];
  // List.sort는 안정 정렬을 보장하지 않으므로 칸 순서까지 비교한다.
  list.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : a.key.index.compareTo(b.key.index);
  });
  return list.take(limit).toList();
}

/// "쇼핑이에요", "정보예요": 마지막 글자에 받침이 있으면 "이에요".
String _copulaFor(String word) {
  final code = word.runes.last - 0xAC00;
  return code >= 0 && code <= 11171 && code % 28 != 0 ? '이에요' : '예요';
}

/// 완료 요약: "요즘 가장 많이 모은 건 / [카테고리]이에요" + 상위 3개. 한 장도 없으면 그리지 않는다.
class AnalysisSummary extends StatelessWidget {
  const AnalysisSummary({super.key, required this.counts});

  final Map<Category, int> counts;

  @override
  Widget build(BuildContext context) {
    final top = topCategories(counts);
    if (top.isEmpty) return const SizedBox.shrink();
    final best = top.first.key;
    final title = AppText.sectionTitle.copyWith(color: AppColors.white);
    final line = top.map((e) => '${e.key.label} ${e.value}장').join(' · ');
    final copula = _copulaFor(best.label);
    return Semantics(
      label: '요즘 가장 많이 모은 건 ${best.label}$copula. $line',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('요즘 가장 많이 모은 건', style: title),
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DecoratedBox(
                key: const ValueKey('summary-highlight'),
                decoration: BoxDecoration(
                  color: AppCategoryColors.of(best),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    best.label,
                    style: title.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
              Text(copula, style: title),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            line,
            style: AppText.caption.copyWith(
              color: AppColors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// 진행 중 안내. 화면이 꺼지면 앱이 백그라운드로 가서 동기화가 멈춘다(앱은 이 화면 동안 화면 꺼짐도 막는다, [SyncGate]).
const keepScreenOnHint = '정리하는 동안 화면을 켜 두세요';

/// 보안 문구: 박스 없이 작은 회색 글씨 한 줄(자물쇠 아이콘 작게). 좁은 화면이나 큰 글자에서는 줄바꿈된다.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  static const text = '은행·메신저·민감한 캡처는 기기 밖으로 전송되지 않아요';

  @override
  Widget build(BuildContext context) {
    final grey = AppColors.white.withValues(alpha: 0.55);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(LucideIcons.lock, size: 12, color: grey),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(fontSize: 12, color: grey),
          ),
        ),
      ],
    );
  }
}

/// 한 줄 고정 높이 글자. [text]가 없어도 자리를 그대로 차지해 아래 레이아웃이 움직이지 않는다.
class _FixedLine extends StatelessWidget {
  const _FixedLine(this.text, {required this.style});

  final String? text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text ?? ' ',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // [Flutter 메모] 글꼴이 달라도 줄 높이를 강제로 같게 한다.
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      style: style,
    );
  }
}

/// 진행 영역: 가는 막대 + 한 줄 안내. 묶음 사이에도 같은 자리를 차지해 레이아웃이 튀지 않는다. 모션 줄이기면 막대 없이 글자만.
class _ProgressSlot extends StatelessWidget {
  const _ProgressSlot({required this.text, required this.working});

  final String? text;

  /// 실제 진행 중인 화면인지(개발용 가짜 값이면 막대를 띄우지 않는다).
  final bool working;

  static const barHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final showBar = working && !AppMotion.reduced(context);
    return Semantics(
      key: const ValueKey('analysis-progress'),
      liveRegion: true,
      label: text ?? '',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: barHeight,
            width: double.infinity,
            child: showBar
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: const LinearProgressIndicator(
                      minHeight: barHeight,
                      color: AppColors.celadon,
                      backgroundColor: Color(0x33FFFFFF),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.s8),
          _FixedLine(
            text,
            style: AppText.body.copyWith(fontSize: 14, color: AppColors.white),
          ),
        ],
      ),
    );
  }
}
