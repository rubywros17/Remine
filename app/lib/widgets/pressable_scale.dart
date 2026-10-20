import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../core/tokens.dart';

/// 누르는 동안 살짝 줄었다가 스프링으로 돌아오는 눌림 반응. 시스템에서 애니메이션 줄이기가 켜져 있으면 반응하지 않는다.
/// 접근성을 위해 [label]을 읽히는 버튼으로 노출한다(안쪽 글자는 중복으로 읽지 않게 제외).
///
/// [Flutter 메모] SpringSimulation은 물리 스프링 값을 시간에 따라 계산해 AnimationController에 태우는 방법이다.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  // 값 범위 제한이 없는(unbounded) 컨트롤러: 스프링이 목표를 살짝 넘겼다 돌아올 수 있다.
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  void _animateTo(double target) {
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    _controller.animateWith(
      SpringSimulation(AppMotion.spring, _controller.value, target, 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      excludeSemantics: widget.label != null,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _animateTo(0.97),
        onTapUp: (_) => _animateTo(1),
        onTapCancel: () => _animateTo(1),
        onTap: widget.onTap,
        child: ScaleTransition(scale: _controller, child: widget.child),
      ),
    );
  }
}
