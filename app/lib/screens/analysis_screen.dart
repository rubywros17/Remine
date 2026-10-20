import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/category.dart';
import '../widgets/home_widgets.dart';
import '../widgets/small_widgets.dart';

/// 첫 분석 화면(정적). 지금은 가짜 진행값이고, 진행 모션은 이후에 더한다.
///
/// 레이아웃: 높이가 넉넉하면 개인정보 안내 카드가 맨 아래에 붙고, 낮으면 내용 전체가 함께 스크롤된다.
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
        // 높이가 넉넉하면 안내 카드가 맨 아래에 붙고, 모자라면 함께 스크롤된다.
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
                        const BrandHeader(
                          pillText: 'DIGGING…',
                          color: AppColors.white,
                        ),
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
                    const PrivacyCard(),
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

/// 썸네일 콜라주(장식). 기울어진 카드 4장과 "→ 쇼핑" 스티커. 크기·위치는 사용 가능한 폭에 비례한다.
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
