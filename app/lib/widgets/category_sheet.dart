import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/category.dart';
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

  bool get _same => _selected == widget.current;

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
                          '이거 어디 서랍이야?',
                          style: AppText.cardTitle.copyWith(fontSize: 22),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text.rich(
                          TextSpan(
                            style: AppText.caption.copyWith(fontSize: 13),
                            children: [
                              const TextSpan(text: 'AI는 '),
                              TextSpan(
                                text: widget.autoCategory.label,
                                style: AppText.caption.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const TextSpan(text: '라고 했어요'),
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
                        _same ? '응, ${widget.current.label} 맞아' : '이 서랍으로 옮기기',
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label: '${category.label}${selected ? ', 선택됨' : ''}',
      child: AnimatedContainer(
        duration: AppMotion.duration(context, MotionDuration.fast),
        curve: AppMotion.standard,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.lemon : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? AppColors.white : AppColors.chip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  categoryIcon(category),
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                category.label,
                style: AppText.label.copyWith(fontSize: 15),
              ),
            ),
            if (selected)
              const Icon(LucideIcons.check, size: 18, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}
