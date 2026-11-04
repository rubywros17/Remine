import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/category.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import 'pressable_scale.dart';
import 'capture_thumb.dart';
import 'small_widgets.dart';

/// 홈 칩 아래 작은 글자 링크 "분석 제외 N장 →": 기기에서만 분류한 숨김 캡처 개수. 0장이면 부르는 쪽에서 숨긴다.
class ExcludedLink extends StatelessWidget {
  const ExcludedLink({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PressableScale(
        onTap: onTap,
        label: '분석 제외 $count장',
        // 글자는 작아도 누르는 영역은 높이 48 이상.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              '분석 제외 $count장 →',
              style: AppText.caption.copyWith(color: AppColors.inkSub),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// 비율 막대의 칸 폭. 칸마다 [AppCategoryColors.barMinSegment]를 먼저 주고 남는 폭을 개수 비율로 나눈다.
/// 칸 폭 합 + 간격 합 = [width]. 폭이 최소 합보다 좁으면 똑같이 나눈다.
List<double> ratioBarWidths(List<int> counts, double width) {
  if (counts.isEmpty) return const [];
  final n = counts.length;
  final available = math.max(0.0, width - AppCategoryColors.barGap * (n - 1));
  const min = AppCategoryColors.barMinSegment;
  if (available < min * n) return List.filled(n, available / n);
  final total = counts.fold(0, (s, c) => s + c);
  final extra = available - min * n;
  return [for (final c in counts) min + extra * c / total];
}

/// 홈 "내 캡처 서랍" 비율 막대: 칩과 같은 순서·데이터에서 0장 카테고리를 뺀 칸. 처음 그려질 때 왼쪽부터 채워진다.
class CategoryRatioBar extends StatelessWidget {
  const CategoryRatioBar({super.key, required this.items});

  /// [CategorySummary.sortedForHome] 그대로(0장은 여기서 뺀다).
  final List<CategorySummaryItem> items;

  @override
  Widget build(BuildContext context) {
    final shown = items.where((i) => i.count > 0).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: shown.map((i) => '${i.category.label} ${i.count}장').join(', '),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final widths = ratioBarWidths([for (final i in shown) i.count], w);
            final bar = ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: SizedBox(
                width: w,
                height: AppCategoryColors.barHeight,
                child: Row(
                  children: [
                    for (var k = 0; k < shown.length; k++) ...[
                      if (k > 0)
                        const SizedBox(width: AppCategoryColors.barGap),
                      SizedBox(
                        width: widths[k],
                        child: ColoredBox(
                          color: AppCategoryColors.of(shown[k].category),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            // [Flutter 메모] TweenAnimationBuilder는 처음 한 번 0→1로 움직이고, 같은 값으로 다시 그려지면 움직이지 않는다.
            // 안쪽 Align(widthFactor: t)이 막대 폭의 t만큼만 차지하고 ClipRect가 나머지를 잘라 왼쪽부터 드러난다.
            // 바깥 Align은 부모의 "꽉 찬 폭" 제약을 풀어 줘야 이 축소가 먹힌다.
            return Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.duration(context, MotionDuration.slow),
                curve: AppMotion.standard,
                builder: (context, t, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: child,
                  ),
                ),
                child: bar,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 막대 칸과 같은 색의 작은 점. 밝은 색은 옅은 테두리로 바탕과 구분한다.
class CategoryDot extends StatelessWidget {
  const CategoryDot({super.key, required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppCategoryColors.dotSize,
      height: AppCategoryColors.dotSize,
      decoration: BoxDecoration(
        color: AppCategoryColors.of(category),
        shape: BoxShape.circle,
        border: AppCategoryColors.needsOutline(category)
            ? Border.all(color: AppCategoryColors.dotOutline)
            : null,
      ),
    );
  }
}

/// 홈의 카테고리 알약: 색 점 · 아이콘 · 이름 · 개수 배지. 모두 같은 테두리 스타일.
class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.item, required this.onTap});

  final CategorySummaryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label: '${item.category.label} ${item.count}장',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.ink, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryDot(category: item.category),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  categoryIcon(item.category),
                  size: 18,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppSpacing.s8),
                // 폭이 모자라면(좁은 화면·큰 글자) 라벨이 줄어들고 말줄임 처리된다.
                Flexible(
                  child: Text(
                    item.category.label,
                    style: AppText.label.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                CountBadge(count: item.count),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 관심사 카드(다크그레이). 주인공은 태그: "#뜨개질"을 크게, 그 아래 같이 캡처한 관심사(`linkedTags`)를 작게.
///
/// 숫자는 세 가지로 보여 준다: 콜라주 위 원형 스티커 "19 / SHOTS", 카드 뒤 옅은 외곽선 워터마크, 왼쪽 아래 점 5칸 게이지.
/// 상태: 마지막 캡처가 [Interest.forgottenAfterDays]일 미만이면 셀라돈 "요즘 빠진 것" + "오늘/어제/N일 전 마지막",
/// 그 이상이면 레몬 "잊은 관심사" + 레몬 테두리 + "N일째 잠자는 중". 누르면 태그 모아보기.
class InterestCard extends StatelessWidget {
  const InterestCard({super.key, required this.interest, required this.onTap});

  final Interest interest;
  final VoidCallback onTap;

  static const _hideCollageBelow = 280.0;

  /// 게이지에서 셀라돈으로 채울 칸 수. 잊은 관심사는 레몬 1칸이라 이 값을 쓰지 않는다.
  static int gaugeFilled(int captureCount) =>
      AppInterestCard.gaugeSteps.where((s) => captureCount >= s).length;

  /// 상태 문구: "오늘 마지막"·"어제 마지막"·"N일 전 마지막", 잊은 것은 "N일째 잠자는 중".
  static String lastSeen(Interest i) => i.forgotten
      ? '${i.dormantDays}일째 잠자는 중'
      : switch (i.dormantDays) {
          0 => '오늘 마지막',
          1 => '어제 마지막',
          final d => '$d일 전 마지막',
        };

  @override
  Widget build(BuildContext context) {
    final i = interest;
    final span = windowLabel(i.spanDays);
    final status = i.forgotten ? '잊은 관심사' : '요즘 빠진 것';
    final linkedTags = i.linkedTags.take(3).toList();
    final white70 = AppColors.white.withValues(alpha: 0.75);
    final accent = i.forgotten ? AppColors.lemon : AppColors.celadon;
    return PressableScale(
      onTap: onTap,
      label:
          '$status ${i.tag}, $span 동안 ${i.captureCount}번 캡처, ${lastSeen(i)}'
          '${linkedTags.isEmpty ? '' : ', 함께 캡처한 관심사 ${linkedTags.join(', ')}'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.darkGray,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: LayoutBuilder(
            builder: (context, box) {
              final collageWidth = box.maxWidth < _hideCollageBelow
                  ? 0.0
                  : (box.maxWidth * 0.36).clamp(72.0, 140.0);
              return Stack(
                children: [
                  Positioned(
                    right: -6,
                    bottom: -AppInterestCard.watermarkSize * 0.22,
                    child: _Watermark(count: i.captureCount),
                  ),
                  if (collageWidth > 0) ...[
                    Positioned(
                      right: 16,
                      top: 12,
                      bottom: 12,
                      width: collageWidth,
                      child: _Collage(captures: i.recent),
                    ),
                    Positioned(
                      right:
                          16 + collageWidth - AppInterestCard.shotsSize * 0.45,
                      top: 6,
                      child: _ShotsSticker(
                        count: i.captureCount,
                        forgotten: i.forgotten,
                      ),
                    ),
                  ],
                  // 글자 영역: 콜라주·스티커와 겹치지 않게 오른쪽을 비우고, 높이는 내용에 맞춘다.
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppInterestCard.minHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        collageWidth > 0
                            ? 16 +
                                  collageWidth +
                                  AppInterestCard.shotsSize * 0.6
                            : 20,
                        16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Sticker(label: status, color: accent),
                              const SizedBox(height: AppSpacing.s8),
                              Text(
                                '#${i.tag}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.display.copyWith(
                                  color: AppColors.white,
                                  height: 1.15,
                                ),
                              ),
                              if (linkedTags.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.s4),
                                Text(
                                  linkedTags.map((t) => '#$t').join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption.copyWith(
                                    color: white70,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.s12),
                            ],
                          ),
                          Row(
                            children: [
                              _Gauge(
                                filled: i.forgotten
                                    ? 1
                                    : gaugeFilled(i.captureCount),
                                color: accent,
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Flexible(
                                child: Text(
                                  lastSeen(i),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption.copyWith(
                                    color: white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 잊은 관심사 레몬 테두리: 맨 위에 그려 콜라주가 덮지 않게 한다.
                  if (i.forgotten)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: const ValueKey('forgotten-border'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            border: Border.all(
                              color: AppColors.lemon,
                              width: AppInterestCard.forgottenBorder,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 카드 뒤 큰 숫자(외곽선만). 장식이라 읽지 않는다.
class _Watermark extends StatelessWidget {
  const _Watermark({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      '$count',
      // 장식이라 글자 크기 설정과 상관없이 그대로 둔다(커지면 태그를 덮는다).
      textScaler: TextScaler.noScaling,
      style: AppText.numHero(size: AppInterestCard.watermarkSize).copyWith(
        color: null,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppInterestCard.watermarkStroke
          ..color = AppInterestCard.watermarkColor,
      ),
    ),
  );
}

/// 콜라주 위에 비스듬히 붙은 원형 스티커 "19 / SHOTS". 흰색, 잊은 관심사는 레몬.
class _ShotsSticker extends StatelessWidget {
  const _ShotsSticker({required this.count, required this.forgotten});

  final int count;
  final bool forgotten;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Transform.rotate(
      angle: AppInterestCard.shotsTilt,
      child: Container(
        key: const ValueKey('shots-sticker'),
        width: AppInterestCard.shotsSize,
        height: AppInterestCard.shotsSize,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: forgotten ? AppColors.lemon : AppColors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: AppColors.cardShadow, blurRadius: 6),
          ],
        ),
        // 원 크기는 고정이라 큰 글꼴에서도 원 안에 들어가게 줄인다.
        child: FittedBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count', style: AppText.brand()),
              Text(
                'SHOTS',
                style: AppText.numBadge().copyWith(
                  fontSize: 8,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 점 5칸 게이지. 앞에서 [filled]칸을 [color]로 채운다.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.filled, required this.color});

  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < AppInterestCard.gaugeSteps.length; k++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              key: ValueKey(k < filled ? 'gauge-on-$k' : 'gauge-off-$k'),
              width: AppInterestCard.gaugeDot,
              height: AppInterestCard.gaugeDot,
              decoration: BoxDecoration(
                color: k < filled ? color : AppInterestCard.gaugeEmpty,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );
}

/// 기울어진 썸네일 3장(장식). 회전은 장식에만 쓴다. 크기는 주어진 영역에 비례한다.
/// 기기 모드에서는 실제 사진, 가짜 데이터 모드에서는 색 블록([CaptureThumb]).
class _Collage extends StatelessWidget {
  const _Collage({required this.captures});

  final List<InterestCapture> captures;

  static const _angles = [-0.2, -0.04, 0.12]; // 라디안 (뒤 → 앞)

  @override
  Widget build(BuildContext context) {
    final shown = captures.take(3).toList().reversed.toList(); // 가장 새 것이 맨 앞
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final thumbWidth = box.maxWidth * 0.5;
          final thumbHeight = (thumbWidth * 1.54).clamp(
            0.0,
            box.maxHeight * 0.85,
          );
          return Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: box.maxWidth * 0.04 + i * box.maxWidth * 0.14,
                  top: 6.0 + i * 8,
                  width: thumbWidth,
                  height: thumbHeight,
                  child: Hero(
                    tag: 'screenshot-${shown[i].id}',
                    child: Transform.rotate(
                      angle: _angles[(i + (3 - shown.length)) % 3],
                      child: CaptureThumb(
                        assetId: shown[i].localAssetId,
                        seed: shown[i].id,
                        radius: 18,
                        size: 240,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 하단 고정 탭바(서랍·관심사·검색). 선택 탭은 연셀라돈 알약 배경.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _tabs = [
    (LucideIcons.archive, '서랍'),
    (LucideIcons.star, '관심사'),
    (LucideIcons.search, '검색'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: PressableScale(
                  onTap: () => onChanged(i),
                  label: '${_tabs[i].$2} 탭${i == index ? ', 선택됨' : ''}',
                  // 칸마다 최소 높이 72. Center(heightFactor: 1)는 내용 높이만 차지해 탭바가 화면 전체로 늘어나지 않는다.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Center(
                      heightFactor: 1,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: AppMotion.duration(
                              context,
                              MotionDuration.base,
                            ),
                            curve: AppMotion.standard,
                            width: 64,
                            height: 34,
                            decoration: BoxDecoration(
                              color: i == index
                                  ? AppColors.celadonSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Icon(
                              _tabs[i].$1,
                              size: 22,
                              color: i == index
                                  ? AppColors.ink
                                  : AppColors.inkSub,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _tabs[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: i == index
                                  ? AppColors.ink
                                  : AppColors.inkSub,
                              fontWeight: i == index
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 장식 회전 각도(라디안)를 id로 고정한다: -max ~ +max.
double decorAngle(int seed, {double max = 0.06}) => ((seed % 5) - 2) / 2 * max;
