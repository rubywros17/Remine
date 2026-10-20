import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import 'pressable_scale.dart';
import 'small_widgets.dart';
import 'thumb_placeholder.dart';

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
                Text(
                  item.category.label,
                  style: AppText.label.copyWith(fontSize: 15),
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
class InterestCard extends StatelessWidget {
  const InterestCard({super.key, required this.interest, required this.onTap});

  final Interest interest;
  final VoidCallback onTap;

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
      child: SizedBox(
        height: 196,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.darkGray,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Stack(
              children: [
                Positioned(
                  right: -6,
                  top: 12,
                  bottom: 12,
                  width: 140,
                  child: _Collage(ids: interest.screenshotIds),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Sticker(label: '잊은 관심사'),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        '×${interest.captureCount}',
                        style: AppText.numXL(color: AppColors.white),
                      ),
                      const Spacer(),
                      Text(
                        '#${interest.tag}',
                        style: AppText.sectionTitle.copyWith(
                          color: AppColors.white,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        '$span 동안 ${interest.captureCount}번 캡처 · ${interest.dormantDays}일째 잠자는 중',
                        style: AppText.caption.copyWith(
                          color: AppColors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
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

/// 기울어진 썸네일 3장(장식). 회전은 장식에만 쓴다.
class _Collage extends StatelessWidget {
  const _Collage({required this.ids});

  final List<int> ids;

  static const _angles = [-0.2, -0.04, 0.12]; // 라디안 (뒤 → 앞)

  @override
  Widget build(BuildContext context) {
    final shown = ids.take(3).toList().reversed.toList(); // 가장 새 것이 맨 앞
    return ExcludeSemantics(
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: 4.0 + i * 22,
              top: 6.0 + i * 8,
              width: 78,
              height: 120,
              child: Hero(
                tag: 'screenshot-${shown[i]}',
                child: Transform.rotate(
                  angle: _angles[(i + (3 - shown.length)) % 3],
                  child: ThumbPlaceholder(seed: shown[i], radius: 18),
                ),
              ),
            ),
        ],
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
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: PressableScale(
                    onTap: () => onChanged(i),
                    label: '${_tabs[i].$2} 탭${i == index ? ', 선택됨' : ''}',
                    child: Center(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 첫 분석 화면 하단의 개인정보 안내 카드 (해요체).
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          children: [
            const Icon(LucideIcons.lock, size: 18, color: AppColors.ink),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                '은행·메신저 캡처, 민감한 정보가 보이는 캡처는 폰 밖으로 안 나가요.',
                style: AppText.body.copyWith(fontSize: 14, height: 1.4),
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
