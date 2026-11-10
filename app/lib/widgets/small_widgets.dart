import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import 'pressable_scale.dart';
import 'wordmark.dart';

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

/// 스티커(관심사 상태·태그 스티커). 기본은 레몬. 장식이라 살짝 기울인다. 눌리지 않는다.
class Sticker extends StatelessWidget {
  const Sticker({
    super.key,
    required this.label,
    this.angle = -0.05,
    this.color = AppColors.lemon,
  });

  final String label;
  final double angle; // 라디안
  final Color color; // 위 글자는 항상 ink라 레몬·셀라돈만

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
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
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.chip,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text('$count', style: AppText.numBadge()),
    );
  }
}

/// 형광펜 밑줄: 글자 상자의 아래 [height](비율)만 [color]로 칠한다. 말줄임된 글자에 두르면 말줄임 끝까지 이어진다.
BoxDecoration highlighterDecoration({
  double height = 0.5,
  Color color = AppColors.lemon,
}) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0, 1 - height, 1 - height, 1],
    colors: [
      color.withValues(alpha: 0),
      color.withValues(alpha: 0),
      color,
      color,
    ],
  ),
);

/// 한 줄 글자(말줄임 가능) 아래에 붙는 형광펜 띠. 띠 윗변을 글자 기준선(baseline)에 맞춰 획과 거의 겹치지 않고,
/// 폭은 실제로 그려진 글자 폭이라 말줄임되면 말줄임표 끝까지만 이어진다.
class BaselineHighlight extends StatelessWidget {
  const BaselineHighlight({
    super.key,
    required this.text,
    required this.style,
    required this.color,
    required this.thickness,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    // 같은 스타일·글자 크기 배율로 기준선 위치를 잰다(Text와 같은 줄 상자).
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: baseline,
          height: thickness,
          child: ColoredBox(
            key: const ValueKey('highlight-band'),
            color: color,
          ),
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
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
              decoration: highlighterDecoration(),
              child: Text(highlight, style: textStyle),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상단 헤더: 왼쪽 `re:mine`([Wordmark]), 오른쪽 알약(날짜·상태). 알약은 폭이 모자라면 줄어든다(`FittedBox`).
/// 글자 폭은 폰트·글자 크기에 따라 달라서 고정 폭을 가정하지 않는다.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.pillText,
    this.color = AppColors.ink,
  });

  final String pillText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Wordmark(color: color),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: color, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(pillText, style: AppText.numBadge(color: color)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
