import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';

/// 격자에서 고를 수 있는 사진 칸. [child](사진)를 칸 가득 채우고 선택 상태를 표시한다.
///
/// - 선택: 사진이 칸 안에서 [AppGesture.selectedPhotoScale]배로 줄고(모서리 반경 유지) 15%만 어두워지며,
///   우상단에 검은 원 + 레몬 체크가 줄어든 사진 모서리에 붙는다. 테두리는 없다.
/// - 미선택: 우상단에 흰 테두리 빈 원(얇은 그림자로 밝은 사진 위에서도 보임) = 고를 수 있다는 표시.
/// - 애니메이션 줄이기면 모션 없이 바로 바뀐다([AppMotion.duration]).
///
/// [Flutter 메모] AnimatedScale·AnimatedPositioned는 값이 바뀌면 알아서 보간해 주는 "암시적 애니메이션"이다.
class SelectableThumb extends StatelessWidget {
  const SelectableThumb({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  static const _radius = 12.0;
  static const _circle = 22.0;
  static const _corner = 6.0;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.duration(context, MotionDuration.fast);
    return LayoutBuilder(
      builder: (context, box) {
        // 축소된 사진의 모서리에 체크 원을 맞추기 위한 한쪽 여백.
        final inset = selected
            ? box.maxWidth * (1 - AppGesture.selectedPhotoScale) / 2
            : 0.0;
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedScale(
                scale: selected ? AppGesture.selectedPhotoScale : 1.0,
                duration: duration,
                curve: AppMotion.standard,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: AppColors.chip, child: child),
                      if (selected)
                        const ColoredBox(color: AppColors.selectionDim),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: AppMotion.standard,
              top: _corner + inset,
              right: _corner + inset,
              child: selected
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: _circle,
                        height: _circle,
                        child: Icon(
                          LucideIcons.check,
                          size: 14,
                          color: AppColors.lemon,
                        ),
                      ),
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: AppColors.white, width: 2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.selectionRingShadow,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: SizedBox(width: _circle, height: _circle),
                    ),
            ),
          ],
        );
      },
    );
  }
}
