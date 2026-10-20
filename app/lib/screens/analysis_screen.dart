import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/category.dart';
import '../widgets/home_widgets.dart';
import '../widgets/small_widgets.dart';

/// 첫 분석 화면(정적). 지금은 가짜 진행값이고, 진행 모션은 이후에 더한다.
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key, this.done = 128, this.total = 300});

  final int done;
  final int total;

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
    return Scaffold(
      backgroundColor: AppColors.darkGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.s16,
            AppSpacing.screenPadding,
            AppSpacing.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('remine.', style: AppText.brand(color: AppColors.white)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: AppColors.white, width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        'DIGGING…',
                        style: AppText.numBadge(color: AppColors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.s32),
                      // 큰 진행 숫자: 셀라돈 on 다크그레이 (대비 4.43:1)
                      Semantics(
                        label: '$total장 중 $done장 꺼냈어요',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$done',
                                style: AppText.numHero(
                                  color: AppColors.celadon,
                                  size: 128,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            Text(
                              '/ $total장 꺼냈어요',
                              style: AppText.sectionTitle.copyWith(
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s32),
                      const _CollageBand(),
                      const SizedBox(height: AppSpacing.s24),
                      Wrap(
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: [
                          for (final e in _counts.entries)
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
                ),
              ),
              const PrivacyCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 썸네일 콜라주(장식). 기울어진 카드 4장과 "→ 쇼핑" 스티커.
class _CollageBand extends StatelessWidget {
  const _CollageBand();

  @override
  Widget build(BuildContext context) {
    const cards = [
      (AppColors.celadonSoft, -0.2, 0.0, 30.0),
      (Color(0xFFDDE9EA), -0.08, 70.0, 6.0),
      (AppColors.white, 0.0, 150.0, 0.0),
      (AppColors.lemon, 0.16, 232.0, 24.0),
    ];
    return ExcludeSemantics(
      child: SizedBox(
        height: 190,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (color, angle, left, top) in cards)
              Positioned(
                left: left,
                top: top,
                width: 84,
                height: 128,
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
            const Positioned(
              left: 156,
              top: -10,
              child: Sticker(label: '→ 쇼핑', angle: -0.05),
            ),
          ],
        ),
      ),
    );
  }
}
