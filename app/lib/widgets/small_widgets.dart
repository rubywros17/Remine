import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import 'pressable_scale.dart';

/// 알약 모양 칩 하나. 선택(레몬)·중립(테두리)·해시태그(연셀라돈) 변형을 한 곳에서 만든다.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.background,
    this.borderColor,
    this.leading,
    this.trailing,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  });

  /// 중립 칩(테두리).
  const AppChip.outlined({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.style,
  }) : background = null,
       borderColor = AppColors.ink,
       padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9);

  /// 선택된 칩(레몬).
  const AppChip.selected({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.style,
  }) : background = AppColors.lemon,
       borderColor = null,
       padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9);

  /// 해시태그(연셀라돈).
  const AppChip.hashtag({super.key, required this.label, this.style})
    : background = AppColors.celadonSoft,
      borderColor = null,
      leading = null,
      trailing = null,
      padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9);

  final String label;
  final Color? background;
  final Color? borderColor;
  final Widget? leading;
  final Widget? trailing;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1.2),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.s8),
            ],
            Flexible(
              child: Text(
                label,
                style: style ?? AppText.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 레몬 스티커(관심사 라벨·태그 스티커). 장식이라 살짝 기울인다. 눌리지 않는다.
class Sticker extends StatelessWidget {
  const Sticker({super.key, required this.label, this.angle = -0.05});

  final String label;
  final double angle; // 라디안

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.lemon,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label, style: AppText.label.copyWith(fontSize: 13)),
        ),
      ),
    );
  }
}

/// 둥근 아이콘 버튼(뒤로 가기·닫기). 터치 영역 48.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final String label; // 스크린 리더용
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// 뒤로 가기(왼쪽 화살표).
class BackButtonCircle extends StatelessWidget {
  const BackButtonCircle({super.key, this.background});

  final Color? background;

  @override
  Widget build(BuildContext context) => RoundIconButton(
    icon: LucideIcons.chevronLeft,
    label: '뒤로',
    background: background,
    onTap: () => Navigator.of(context).maybePop(),
  );
}

/// 개수 배지(원형에 가까운 알약).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.dark = false});

  final int count;

  /// true면 ink 채움 + 흰 글자(가장 많은 카테고리 알약 안).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppColors.ink : AppColors.chip,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        '$count',
        style: AppText.numBadge(color: dark ? AppColors.white : AppColors.ink),
      ),
    );
  }
}

/// 제목의 핵심 단어에 레몬 형광펜(글자 아래쪽 절반을 칠한 띠)을 긋는다.
///
/// [Flutter 메모] WidgetSpan은 글자 흐름 안에 위젯을 끼워 넣는다. 여기서는 단어를 그라데이션(경계가 딱 끊어지는)
/// 배경 위에 얹어 형광펜처럼 보이게 한다.
class HighlighterText extends StatelessWidget {
  const HighlighterText({
    super.key,
    required this.before,
    required this.highlight,
    this.style,
  });

  final String before;
  final String highlight;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? AppText.display;
    return Text.rich(
      TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.5, 0.5, 1],
                  colors: [
                    Color(0x00EDE7B3),
                    Color(0x00EDE7B3),
                    AppColors.lemon,
                    AppColors.lemon,
                  ],
                ),
              ),
              child: Text(highlight, style: textStyle),
            ),
          ),
        ],
      ),
    );
  }
}
