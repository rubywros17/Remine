import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';

/// 격자에서 고를 수 있는 사진 칸. [child](사진)를 칸 가득 채우고 선택 상태를 표시한다.
///
/// - 선택: 사진이 칸 안에서 [AppGesture.selectedPhotoScale]배로 줄고(모서리 반경 유지) 15%만 어두워진다.
///   줄어든 사진 **바깥쪽**에 3px 딥 셀라돈 테두리가 같은 모션으로 나타나고, 우상단의 검은 원 + 레몬 체크는
///   테두리까지 포함한 모서리에 붙는다.
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
  static const _borderWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.duration(context, MotionDuration.fast);
    return LayoutBuilder(
      builder: (context, box) {
        // 줄어든 사진이 칸 가장자리에서 떨어진 거리. 테두리는 그 바깥 3px, 체크 원은 테두리 바깥 모서리 기준.
        final photoInset = selected
            ? box.maxWidth * (1 - AppGesture.selectedPhotoScale) / 2
            : 0.0;
        final borderInset = photoInset - (selected ? _borderWidth : 0.0);
        // 사진 모서리는 배율만큼 같이 줄어든다 → 테두리 반경은 줄어든 반경 + 두께.
        final borderRadius =
            _radius * AppGesture.selectedPhotoScale + _borderWidth;
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
              left: borderInset,
              top: borderInset,
              right: borderInset,
              bottom: borderInset,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: duration,
                  curve: AppMotion.standard,
                  child: DecoratedBox(
                    key: const ValueKey('thumb-border'),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.celadonDeep,
                        width: _borderWidth,
                      ),
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: duration,
              curve: AppMotion.standard,
              top: _corner + borderInset,
              right: _corner + borderInset,
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
