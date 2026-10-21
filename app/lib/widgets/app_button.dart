import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'pressable_scale.dart';

/// 알약 버튼. 기본은 레몬 채움, [outlined]면 테두리만. 글자가 길면 줄바꿈되고 높이가 늘어난다.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52, minWidth: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: outlined ? null : AppColors.lemon,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: outlined
                ? Border.all(color: AppColors.ink, width: 1.2)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
