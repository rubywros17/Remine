import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import 'pressable_scale.dart';
import 'capture_thumb.dart';
import 'small_widgets.dart';

/// 홈의 "분석 제외" 알약: 기기에서만 분류한 숨김 캡처 개수. 연한 테두리로 카테고리 알약과 구분한다.
class ExcludedPill extends StatelessWidget {
  const ExcludedPill({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label: '분석 제외 $count장',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.lock, size: 18, color: AppColors.inkSub),
                const SizedBox(width: AppSpacing.s8),
                Flexible(
                  child: Text(
                    '분석 제외 $count',
                    style: AppText.label.copyWith(
                      fontSize: 15,
                      color: AppColors.inkSub,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈의 카테고리 알약: 아이콘 · 이름 · 개수 배지. 가장 많은 카테고리([filled])만 셀라돈으로 채운다.
class CategoryPill extends StatelessWidget {
  const CategoryPill({
    super.key,
    required this.item,
    required this.filled,
    required this.onTap,
  });

  final CategorySummaryItem item;
  final bool filled;
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
            color: filled ? AppColors.celadon : AppColors.background,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: filled
                ? null
                : Border.all(color: AppColors.ink, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                CountBadge(count: item.count, dark: filled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 잊은 관심사 카드(다크그레이). 오른쪽에는 장식용으로 기울어진 썸네일 3장이 있고 Hero로 이어진다.
///
/// 높이는 내용에 맞춰 자란다(최소 196). 글자가 커지거나 줄이 늘어도 넘치지 않고, 콜라주는 카드 폭에 비례하며
/// 카드가 너무 좁으면 장식이라 숨긴다.
class InterestCard extends StatelessWidget {
  const InterestCard({super.key, required this.interest, required this.onTap});

  final Interest interest;
  final VoidCallback onTap;

  static const _minHeight = 196.0;
  static const _hideCollageBelow = 280.0;

  @override
  Widget build(BuildContext context) {
    final weeks = interest.spanDays ~/ 7;
    final span = interest.spanDays % 7 == 0
        ? '$weeks주'
        : '${interest.spanDays}일';
    return PressableScale(
      onTap: onTap,
      label:
          '잊은 관심사 ${interest.tag}, $span 동안 ${interest.captureCount}번 캡처, ${interest.dormantDays}일째 잠자는 중',
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
                  if (collageWidth > 0)
                    Positioned(
                      right: 16,
                      top: 12,
                      bottom: 12,
                      width: collageWidth,
                      child: _Collage(captures: interest.recent),
                    ),
                  // 글자 영역: 콜라주와 겹치지 않게 오른쪽을 비우고, 높이는 내용에 맞춘다.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _minHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        collageWidth > 0 ? 16 + collageWidth * 0.9 : 20,
                        16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Sticker(label: '잊은 관심사'),
                              const SizedBox(height: AppSpacing.s8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '×${interest.captureCount}',
                                  style: AppText.numXL(color: AppColors.white),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${interest.tag}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.sectionTitle.copyWith(
                                  color: AppColors.white,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                '$span 동안 ${interest.captureCount}번 캡처 · ${interest.dormantDays}일째 잠자는 중',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(
                                  color: AppColors.white.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
