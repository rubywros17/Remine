import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/remote/sync_status.dart';
import '../models/category.dart';
import '../widgets/app_button.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/small_widgets.dart';

/// 첫 분석 화면. [status]가 있으면 실제 동기화 진행(장수·방금 분류된 캡처·카테고리별 개수·남은 예상 시간)을 보여 주고,
/// 없으면(개발용 `START_SCREEN=analysis`, 테스트) 가짜 진행값을 보여 준다.
///
/// - 진행 중: [onHome]이 있으면 "홈에서 먼저 볼래요"로 분석 중에도 홈에 나갈 수 있다(분석은 계속된다).
/// - 끝나면: 자동으로 넘어가지 않고 "N장 꺼냈어요" 완료 상태와 [홈으로] 버튼을 보여 준다.
///
/// 레이아웃: 높이가 넉넉하면 보안 문구가 맨 아래에 붙고, 낮으면 내용 전체가 함께 스크롤된다.
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
      return _Body(
        done: done,
        total: total,
        counts: _counts,
        recent: const [],
        onHome: onHome,
      );
    }
    // [Flutter 메모] ListenableBuilder는 ChangeNotifier가 알릴 때마다 builder만 다시 실행한다.
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final eta = status.eta;
        return _Body(
          done: status.done,
          total: status.total,
          counts: status.counts,
          recent: status.recent,
          fake: false,
          finished: status.finished,
          issueText: status.finished ? status.issueMessage : null,
          etaText: eta != null
              ? formatEta(eta)
              : status.running
              ? '남은 시간을 계산하고 있어요'
              : null,
          waitingText: status.waitingMessage,
          onHome: onHome,
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
    required this.recent,
    this.fake = true,
    this.finished = false,
    this.issueText,
    this.etaText,
    this.waitingText,
    this.onHome,
  });

  final int done;
  final int total;
  final Map<Category, int> counts;
  final List<RecentShot> recent;

  /// 가짜 진행값(개발용)인지. 가짜면 장식 카드 띠를 보여 준다.
  final bool fake;
  final bool finished;
  final String? issueText;
  final String? etaText;
  final String? waitingText;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGray,
      body: SafeArea(
        // 높이가 넉넉하면 보안 문구가 맨 아래에 붙고, 모자라면 함께 스크롤된다.
        // [Flutter 메모] 스크롤 안의 Column은 높이가 무한이라 Expanded를 못 쓴다. 대신 "최소 높이 = 화면 높이"로 두고
        // mainAxisAlignment.spaceBetween으로 남는 높이를 위/아래 묶음 사이에 둔다.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s16,
                  AppSpacing.screenPadding,
                  AppSpacing.s16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        ),
                        if (issueText != null) ...[
                          const SizedBox(height: AppSpacing.s8),
                          Text(
                            issueText!,
                            style: AppText.body.copyWith(
                              fontSize: 14,
                              color: AppColors.lemon,
                            ),
                          ),
                        ],
                        if (waitingText != null) ...[
                          const SizedBox(height: AppSpacing.s16),
                          _WorkingNote(text: waitingText!),
                        ],
                        if (!finished) ...[
                          const SizedBox(height: AppSpacing.s12),
                          Text(
                            keepScreenOnHint,
                            style: AppText.caption.copyWith(
                              color: AppColors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.s32),
                        fake
                            ? const _CollageBand()
                            : _RecentBand(shots: recent),
                        const SizedBox(height: AppSpacing.s24),
                        Text(
                          '지금까지 찾은 것',
                          style: AppText.label.copyWith(
                            color: AppColors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s8,
                          children: [
                            for (final e in counts.entries)
                              AppChip(
                                label: e.key.label,
                                background: AppColors.white,
                                trailing: CountBadge(count: e.value),
                                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s24),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (onHome != null) ...[
                          Center(
                            child: AppButton(
                              label: finished ? '홈으로' : '홈에서 먼저 볼래요',
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
    );
  }
}

/// 큰 진행 숫자. 진행 중에는 "N / M장 꺼냈어요", 끝나면 "N장 꺼냈어요".
class _Counter extends StatelessWidget {
  const _Counter({
    required this.done,
    required this.total,
    required this.finished,
    required this.etaText,
  });

  final int done;
  final int total;
  final bool finished;
  final String? etaText;

  /// 끝났는데 꺼낸 게 없을 때(새 캡처 없음·서버에 닿지 못함).
  static const _noneText = '새로 꺼낼 캡처가 없어요';

  String get _finishedText => done == 0 ? _noneText : '$done장 꺼냈어요';

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
                ? (done == 0 ? _finishedText : '장 꺼냈어요')
                : '/ $total장 꺼냈어요',
            style: AppText.sectionTitle.copyWith(color: AppColors.white),
          ),
          if (!finished && etaText != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              etaText!,
              style: AppText.body.copyWith(color: AppColors.celadonSoft),
            ),
          ],
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

/// 방금 분류된 실제 캡처 썸네일 + 그 카테고리 라벨. 기울어진 카드 4장이 왼쪽 → 오른쪽으로 오래된 순으로 놓이고,
/// 아직 분류된 게 모자라면 빈 카드가 남는다. 크기·위치는 사용 가능한 폭에 비례한다.
class _RecentBand extends StatelessWidget {
  const _RecentBand({required this.shots});

  /// 최신이 앞.
  final List<RecentShot> shots;

  // (기울기(라디안), 왼쪽 위치(남는 폭 비율), 위쪽 위치(카드 높이 비율))
  static const _slots = [
    (-0.2, 0.0, 0.23),
    (-0.08, 0.28, 0.05),
    (0.0, 0.58, 0.0),
    (0.16, 1.0, 0.19),
  ];

  @override
  Widget build(BuildContext context) {
    // 오른쪽 칸일수록 최근 것: 오래된 순으로 뒤집어 오른쪽 끝에 맞춘다.
    final ordered = shots.reversed.toList();
    final empty = _slots.length - ordered.length;
    return Semantics(
      label: shots.isEmpty
          ? '아직 분류된 캡처가 없어요'
          : '방금 꺼낸 캡처: ${shots.map((s) => s.category.label).join(', ')}',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
          final cardWidth = (width * 0.26).clamp(36.0, 96.0);
          final cardHeight = cardWidth * 1.5;
          final span = width - cardWidth; // 카드가 움직일 수 있는 가로 범위
          return SizedBox(
            height: cardHeight * 1.45,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < _slots.length; i++)
                  Positioned(
                    left: _slots[i].$2 * span,
                    top: _slots[i].$3 * cardHeight,
                    width: cardWidth,
                    height: cardHeight,
                    child: Transform.rotate(
                      angle: _slots[i].$1,
                      child: i < empty
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.tile,
                                ),
                              ),
                            )
                          : _ShotCard(shot: ordered[i - empty]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.shot});

  final RecentShot shot;

  @override
  Widget build(BuildContext context) {
    return CaptureThumb(
      key: ValueKey('recent-${shot.assetId}'),
      assetId: shot.assetId,
      seed: shot.assetId.hashCode.abs(),
      radius: AppRadii.tile,
      size: 240,
      child: Positioned(
        left: 4,
        right: 4,
        bottom: 4,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.lemon,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                shot.category.label,
                style: AppText.label.copyWith(fontSize: 11),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 가짜 진행값(개발용)의 장식 카드 띠. 기울어진 카드 4장과 "→ 쇼핑" 스티커.
class _CollageBand extends StatelessWidget {
  const _CollageBand();

  // (색, 기울기(라디안), 왼쪽 위치(남는 폭 비율), 위쪽 위치(카드 높이 비율))
  static const _cards = [
    (AppColors.celadonSoft, -0.2, 0.0, 0.23),
    (Color(0xFFDDE9EA), -0.08, 0.28, 0.05),
    (AppColors.white, 0.0, 0.58, 0.0),
    (AppColors.lemon, 0.16, 1.0, 0.19),
  ];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
          final cardWidth = (width * 0.26).clamp(36.0, 96.0);
          final cardHeight = cardWidth * 1.5;
          final span = width - cardWidth; // 카드가 움직일 수 있는 가로 범위
          return SizedBox(
            height: cardHeight * 1.45,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final (color, angle, left, top) in _cards)
                  Positioned(
                    left: left * span,
                    top: top * cardHeight,
                    width: cardWidth,
                    height: cardHeight,
                    child: Transform.rotate(
                      angle: angle,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AppRadii.tile),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: (0.58 * span - 6).clamp(0.0, span),
                  top: -10,
                  child: const Sticker(label: '→ 쇼핑', angle: -0.05),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "N장을 분류하는 중" 안내. 서버 응답을 기다리는 동안 숫자가 안 바뀌어도 멈춘 게 아니라는 걸 막대가 움직여 보여 준다.
/// 모션 줄이기 설정이면 움직이는 막대 없이 글자만 보여 준다.
class _WorkingNote extends StatelessWidget {
  const _WorkingNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!AppMotion.reduced(context)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: const LinearProgressIndicator(
                minHeight: 4,
                color: AppColors.celadon,
                backgroundColor: Color(0x33FFFFFF),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          Text(
            text,
            style: AppText.body.copyWith(fontSize: 14, color: AppColors.white),
          ),
        ],
      ),
    );
  }
}
