import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 가짜 썸네일: 실제 스크린샷 대신 색 블록. [seed]로 색 쌍을 고정해 같은 캡처는 항상 같은 색이다.
class ThumbPlaceholder extends StatelessWidget {
  const ThumbPlaceholder({
    super.key,
    required this.seed,
    this.radius = AppRadii.card,
    this.child,
  });

  final int seed;
  final double radius;

  /// 날짜 배지처럼 위에 올릴 것.
  final Widget? child;

  static (Color, Color) colorsFor(int seed) =>
      AppThumbs.palette[seed % AppThumbs.palette.length];

  @override
  Widget build(BuildContext context) {
    final (background, block) = colorsFor(seed);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 0.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(radius * 0.45),
                  ),
                ),
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}
