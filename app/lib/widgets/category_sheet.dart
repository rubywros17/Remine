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
                              // 이름만 굵게, 조사(로/으로)는 보통 굵기.
                              TextSpan(
                                text: widget.autoCategory.label,
                                style: AppText.caption.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${withRo(widget.autoCategory.label).substring(widget.autoCategory.label.length)} 분류했어요',
                              ),
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
                            // 다른 칸을 고른 동안 원래 칸은 점선 테두리로 표시한다.
                            original: c == widget.current && c != _selected,
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

/// 칸 하나: [색 점 · 아이콘 · 이름]은 왼쪽부터, 장수 배지는 오른쪽 끝(모든 칸의 숫자가 세로로 같은 줄). 이름은 말줄임하지 않는다.
/// 칸 높이·모서리·테두리·이름 글자·아이콘 크기는 수정 전(5095f48 이전) 값 그대로이고 줄이지 않는다.
/// 폭이 모자라면 배지 여백 → 요소 간격 → 칸 안쪽 여백 순서로 줄이고, 그래도 모자라면 배지만 숨긴다([fitCategoryTile]).
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.original,
    required this.count,
    required this.onTap,
  });

  final Category category;
  final bool selected;

  /// 시트를 열 때의 카테고리인데 지금은 다른 칸이 선택돼 있다 → 차콜 점선 테두리.
  final bool original;

  /// 아직 불러오지 못했으면 null(배지 자리는 비워 두고 크기만 잡는다).
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.ink;
    final nameStyle = AppText.label.copyWith(
      fontSize: CategoryTileSize.nameFontSize,
      color: fg,
    );
    final badgeStyle = AppText.numBadge(color: fg).copyWith(fontSize: 12);
    final badgeText = countBadgeText(count ?? 0);
    final border = selected
        ? CategoryTileSize.borderSelected
        : CategoryTileSize.border;
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
          // 테두리 1→2 전환 중에도 넘치지 않게 폭은 늘 두꺼운 테두리 기준으로 잡는다.
          final fit = fitCategoryTile(
            available: box.maxWidth - CategoryTileSize.borderSelected * 2,
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
          final tile = AnimatedContainer(
            duration: AppMotion.duration(context, MotionDuration.fast),
            curve: AppMotion.standard,
            constraints: const BoxConstraints(
              minHeight: CategoryTileSize.minHeight,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.darkGray : AppColors.white,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              border: Border.all(
                // 원래 칸은 실선 대신 위에 점선을 그린다(두께 자리는 그대로).
                color: selected
                    ? AppColors.darkGray
                    : original
                    ? Colors.transparent
                    : AppColors.border,
                width: border,
              ),
            ),
            // 여백은 애니메이션하지 않는다(배지 숫자가 바뀌는 순간 옛 여백과 겹쳐 넘치지 않게).
            // 테두리가 얇은 칸은 그 차이만큼 여백을 더해, 선택 칸과 내용·배지 자리가 같게 한다.
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                fit.padLeft + (CategoryTileSize.borderSelected - border),
                0,
                fit.padRight + (CategoryTileSize.borderSelected - border),
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    CategoryDot(category: category, size: 8),
                    SizedBox(width: fit.gap),
                    Icon(
                      categoryIcon(category),
                      size: CategoryTileSize.iconSize,
                      color: fg,
                    ),
                    SizedBox(width: fit.gap),
                    Text(
                      category.label,
                      style: nameStyle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                    if (fit.showBadge) ...[
                      SizedBox(width: fit.gap),
                      const Spacer(), // 배지는 오른쪽 끝
                      Visibility(
                        visible: count != null,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Container(
                          key: ValueKey('count-badge-${category.code}'),
                          height: 22,
                          padding: EdgeInsets.symmetric(
                            horizontal: fit.badgePad,
                          ),
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
                  ],
                ),
              ),
            ),
          );
          if (!original) return tile;
          return CustomPaint(
            key: ValueKey('original-dashed-${category.code}'),
            foregroundPainter: const DashedBorderPainter(
              color: AppColors.darkGray,
              width: CategoryTileSize.originalDash,
              radius: AppRadii.tile,
            ),
            child: tile,
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

/// 칸 크기 값. 수정 전(5095f48 이전) 시트와 같고, 공간이 모자라도 줄이지 않는다.
abstract final class CategoryTileSize {
  static const double minHeight = 64;
  static const double border = 1;
  static const double borderSelected = 2;
  static const double nameFontSize = 15;
  static const double iconSize = 18;

  /// 원래 칸 점선 두께(다른 칸이 선택돼 있을 때).
  static const double originalDash = 1.5;
}

/// 둥근 사각형 점선 테두리. Flutter에는 점선 Border가 없어 경로를 잘라 그린다.
///
/// [Flutter 메모] PathMetric은 경로를 길이로 다루게 해 준다. extractPath(시작, 끝)로 대시 한 토막씩 잘라 그린다.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.width,
    required this.radius,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double width;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.width != width || old.radius != radius;
}

/// 장수 배지 글자: 999를 넘으면 "999+".
String countBadgeText(int count) => count > 999 ? '999+' : '$count';

/// 칸 안 여백·간격. 기본은 안쪽 왼쪽 10 · 오른쪽 8, 요소 간격 6, 배지 좌우 6.
typedef CategoryTileFit = ({
  double padLeft,
  double padRight,
  double gap,
  double badgePad,
  bool showBadge,
});

/// 내용이 [available]에 들어가게 배지 여백(6→2) → 요소 간격(6→2) → 칸 안쪽 여백(10/8→2/2) 순서로 줄인다.
/// 그래도 모자라면 배지를 숨기고(배지 몫의 간격도 뺀다) 여백을 다시 기본값부터 맞춘다.
/// 글자·아이콘 크기는 건드리지 않는다. 배지를 숨겨도 모자라면 최소값을 돌려준다.
CategoryTileFit fitCategoryTile({
  required double available,
  required double nameWidth,
  required double badgeTextWidth,
}) {
  const dot = 8.0, icon = CategoryTileSize.iconSize, min = 2.0;

  CategoryTileFit fit({required bool badge}) {
    var padL = 10.0, padR = 8.0, gap = 6.0, badgePad = badge ? 6.0 : 0.0;
    final gaps = badge ? 3 : 2;
    final fixed = dot + icon + nameWidth + (badge ? badgeTextWidth : 0);
    double over() =>
        padL + padR + fixed + badgePad * 2 + gap * gaps - available;

    if (badge && over() > 0) {
      badgePad = (badgePad - over() / 2).clamp(min, badgePad);
    }
    if (over() > 0) gap = (gap - over() / gaps).clamp(min, gap);
    if (over() > 0) {
      // 좌우를 같은 비율로 줄인다.
      final room = (padL - min) + (padR - min);
      final ratio = (over() / room).clamp(0.0, 1.0);
      padL -= (padL - min) * ratio;
      padR -= (padR - min) * ratio;
    }
    return (
      padLeft: padL,
      padRight: padR,
      gap: gap,
      badgePad: badgePad,
      showBadge: badge && over() <= 0.01,
    );
  }

  final withBadge = fit(badge: true);
  return withBadge.showBadge ? withBadge : fit(badge: false);
}
