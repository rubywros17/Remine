import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/category.dart';
import '../data/remine_store.dart';
import 'home_widgets.dart' show CategoryDot;
import 'pressable_scale.dart';
import 'small_widgets.dart';

/// 카테고리 수정 시트를 연다. 사용자가 고른 카테고리를 돌려주고, 닫으면 null.
/// 저장은 호출한 쪽이 한다(같은 값이어도 저장된다 = 사용자 확인).
///
/// [Flutter 메모] showModalBottomSheet는 아래에서 올라오는 시트를 띄우고, Navigator.pop(값)으로 값을 돌려준다.
Future<Category?> showCategorySheet(
  BuildContext context, {
  required Category current,
  required Category autoCategory,
}) {
  final duration = AppMotion.duration(context, MotionDuration.slow);
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
      curve: AppMotion.emphasized,
    ),
    builder: (_) => CategorySheet(current: current, autoCategory: autoCategory),
  );
}

class CategorySheet extends StatefulWidget {
  const CategorySheet({
    super.key,
    required this.current,
    required this.autoCategory,
  });

  final Category current;
  final Category autoCategory;

  @override
  State<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<CategorySheet> {
  late Category _selected = widget.current;

  /// 칸마다 붙는 장수(홈 막대와 같은 저장소 요약, 휴지통 제외). 불러오기 전에는 null.
  Map<Category, int>? _counts;
  bool _countsRequested = false;

  bool get _same => _selected == widget.current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_countsRequested) return;
    _countsRequested = true;
    final store = RemineScope.maybeOf(context);
    if (store == null) return;
    store.repository.summary().then((summary) {
      if (!mounted) return;
      setState(
        () =>
            _counts = {for (final c in summary.categories) c.category: c.count},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '어느 서랍에 넣을까요?',
                          style: AppText.cardTitle.copyWith(fontSize: 22),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text.rich(
                          TextSpan(
                            style: AppText.caption.copyWith(fontSize: 13),
                            children: [
                              const TextSpan(text: 'AI는 '),
                              TextSpan(
                                text: withRo(widget.autoCategory.label),
                                style: AppText.caption.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const TextSpan(text: ' 분류했어요'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  RoundIconButton(
                    icon: LucideIcons.x,
                    label: '닫기',
                    background: AppColors.chip,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              // 2열 타일. 마지막(기타)은 왼쪽 열에 온다.
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - AppSpacing.s12) / 2;
                  return Wrap(
                    spacing: AppSpacing.s12,
                    runSpacing: AppSpacing.s12,
                    children: [
                      for (final c in Category.values)
                        SizedBox(
                          width: width,
                          child: _CategoryTile(
                            category: c,
                            selected: c == _selected,
                            count: _counts?[c],
                            onTap: () => setState(() => _selected = c),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.s20),
              PressableScale(
                onTap: () => Navigator.of(context).pop(_selected),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.darkGray,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: Center(
                      child: Text(
                        _same
                            ? '${widget.current.label} 그대로 둘게요'
                            : '${withRo(_selected.label)} 옮길게요',
                        style: AppText.label.copyWith(
                          color: AppColors.white,
                          fontSize: 16,
                        ),
                      ),
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

/// 칸 하나: [색 점 · 아이콘 · 이름 · 장수 배지]를 한 묶음으로 가운데 정렬한다. 이름은 말줄임하지 않는다.
/// 폭이 모자라면 글자 크기 대신 배지 여백 → 요소 간격 → 칸 안쪽 여백 순서로 줄인다([fitCategoryTile]).
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final Category category;
  final bool selected;

  /// 아직 불러오지 못했으면 null(배지 자리는 비워 두고 크기만 잡는다).
  final int? count;
  final VoidCallback onTap;

  static const _border = 1.0;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.ink;
    final nameStyle = AppText.label.copyWith(fontSize: 15, color: fg);
    final badgeStyle = AppText.numBadge(color: fg).copyWith(fontSize: 12);
    final badgeText = countBadgeText(count ?? 0);
    return PressableScale(
      onTap: onTap,
      label:
          '${category.label}${count == null ? '' : ' $count장'}'
          '${selected ? ', 선택됨' : ''}',
      child: LayoutBuilder(
        builder: (context, box) {
          // 측정은 Text가 실제로 쓰는 스타일(테마 기본 스타일과 합친 것)로 한다.
          final base = DefaultTextStyle.of(context).style;
          final scaler = MediaQuery.textScalerOf(context);
          final fit = fitCategoryTile(
            available: box.maxWidth - _border * 2,
            nameWidth: _textWidth(
              category.label,
              base.merge(nameStyle),
              scaler,
            ),
            badgeTextWidth: _textWidth(
              badgeText,
              base.merge(badgeStyle),
              scaler,
            ),
          );
          return AnimatedContainer(
            duration: AppMotion.duration(context, MotionDuration.fast),
            curve: AppMotion.standard,
            constraints: const BoxConstraints(minHeight: 64),
            padding: EdgeInsets.fromLTRB(fit.padLeft, 0, fit.padRight, 0),
            decoration: BoxDecoration(
              color: selected ? AppColors.darkGray : AppColors.white,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              border: Border.all(
                color: selected ? AppColors.darkGray : AppColors.border,
                width: _border,
              ),
            ),
            // 여백을 다 줄여도 모자라는 극단적인 경우(아주 좁은 창·대체 글꼴)에만 한 줄 전체를 비율대로 줄인다.
            // 들어맞으면 scaleDown은 아무것도 하지 않는다.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CategoryDot(category: category, size: 8),
                    SizedBox(width: fit.gap),
                    Icon(categoryIcon(category), size: 20, color: fg),
                    SizedBox(width: fit.gap),
                    Text(
                      category.label,
                      style: nameStyle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                    SizedBox(width: fit.gap),
                    Visibility(
                      visible: count != null,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Container(
                        key: ValueKey('count-badge-${category.code}'),
                        height: 22,
                        padding: EdgeInsets.symmetric(horizontal: fit.badgePad),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.countBadgeOnDark
                              : AppColors.countBadge,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          badgeText,
                          style: badgeStyle,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static double _textWidth(String s, TextStyle style, TextScaler scaler) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = p.width;
    p.dispose();
    return w;
  }
}

/// 장수 배지 글자: 999를 넘으면 "999+".
String countBadgeText(int count) => count > 999 ? '999+' : '$count';

/// 칸 안 여백·간격. 기본은 안쪽 왼쪽 10 · 오른쪽 8, 요소 간격 6, 배지 좌우 6.
typedef CategoryTileFit = ({
  double padLeft,
  double padRight,
  double gap,
  double badgePad,
});

/// 내용이 [available]에 들어가게 배지 여백(6→2) → 요소 간격(6→2) → 칸 안쪽 여백(10/8→2/2) 순서로 줄인다.
/// 글자 크기는 줄이지 않는다. 다 줄여도 모자라면 최소값을 돌려준다(그때는 칸이 한 줄 전체를 줄여 담는다).
CategoryTileFit fitCategoryTile({
  required double available,
  required double nameWidth,
  required double badgeTextWidth,
}) {
  const dot = 8.0, icon = 20.0, min = 2.0;
  var padL = 10.0, padR = 8.0, gap = 6.0, badgePad = 6.0;
  double over() =>
      padL +
      padR +
      dot +
      icon +
      nameWidth +
      badgeTextWidth +
      badgePad * 2 +
      gap * 3 -
      available;

  if (over() > 0) badgePad = (badgePad - over() / 2).clamp(min, badgePad);
  if (over() > 0) gap = (gap - over() / 3).clamp(min, gap);
  if (over() > 0) {
    // 좌우를 같은 비율로 줄인다.
    final room = (padL - min) + (padR - min);
    final ratio = (over() / room).clamp(0.0, 1.0);
    padL -= (padL - min) * ratio;
    padR -= (padR - min) * ratio;
  }
  return (padLeft: padL, padRight: padR, gap: gap, badgePad: badgePad);
}
