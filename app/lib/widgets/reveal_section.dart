import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/tokens.dart';

/// 섹션의 "더 보기"로 펼치는 부분: [cards](처음엔 숨은 카드들)과 그 아래 버튼 자리("더 보기" ↔ "접기").
///
/// 펼치기: 높이가 부드럽게 늘고, 카드는 위에서부터 차례로 페이드 + 아래에서 올라온다. "더 보기"는 먼저 사라지고
/// "접기"는 마지막 카드가 다 나온 뒤 나타난다. 접기: 카드가 한꺼번에 사라지며 높이가 준다. 값은 [AppReveal].
///
/// **보이는 만큼만 움직인다**: 카드가 많아도(38장) 적을 때(2장)와 같은 속도로 보이게, 높이 애니메이션은
/// 화면에 보이는 구간까지만 하고 화면 밖 부분은 바로 늘리거나 줄인다. 접을 때 섹션 머리([header])가 화면 위로
/// 멀리(화면 1개 이상) 지나가 있으면 스크롤을 먼저 머리 근처(화면 0.5개 위)로 옮기고 남은 구간만 부드럽게 간다.
/// 이때 버튼 자리는 옮기기 전과 같은 화면 위치에서 시작해 튀어 보이지 않는다.
///
/// 열림 여부는 부모가 정하고([open]), 이 위젯은 그 사이를 움직이기만 한다. 움직이는 중에 [open]이 또 바뀌면
/// 지금 위치에서 새 목표로 이어서 간다(연타해도 꼬이지 않는다). "애니메이션 줄이기"면 바로 바뀐다.
///
/// [Flutter 메모] 카드 위젯은 부모가 한 번 만들어 넘기고, 여기서는 매 프레임 바깥의 투명도·위치만 바꾼다.
/// 그래서 움직이는 동안 카드(사진)는 다시 만들어지지 않는다.
class RevealSection extends StatefulWidget {
  const RevealSection({
    super.key,
    required this.open,
    required this.cards,
    required this.more,
    required this.collapse,
    required this.onCollapse,
    this.header,
  });

  final bool open;
  final List<Widget> cards;
  final Widget more;

  /// "접기" 버튼. 받은 onTap을 눌림에 연결한다(스크롤을 먼저 맞춘 뒤 [onCollapse]를 부른다).
  final Widget Function(VoidCallback onTap) collapse;

  /// 부모가 [open]을 false로 바꾼다.
  final VoidCallback onCollapse;

  /// 섹션 머리. 접을 때 화면 위로 지나가 있으면 여기까지 스크롤한다.
  final GlobalKey? header;

  @override
  State<RevealSection> createState() => _RevealSectionState();
}

class _RevealSectionState extends State<RevealSection>
    with TickerProviderStateMixin {
  /// 높이 진행(0 = 접힘, 1 = 다 펼침). 곡선은 animateTo에서 준다.
  late final AnimationController _size;

  /// 카드·버튼 진행(펼칠 때는 차례로 나타나는 시간축, 접을 때는 한꺼번에 사라지는 정도).
  late final AnimationController _fade;

  final _boxKey = GlobalKey();

  bool _closing = false;

  /// 접기를 시작할 때의 [_fade] 값. 접는 동안 각 카드 투명도를 그 순간 값에서 비례해 줄인다.
  double _closeFrom = 1;

  /// 움직이는 높이의 상한(화면에 보이는 구간). 이 아래는 화면 밖이라 바로 늘리고 줄인다.
  double _cap = double.infinity;

  /// 접는 중에는 진행이 1이어도 [_cap]까지만 보인다(화면 밖 부분은 시작하자마자 줄인다).
  bool _capped = false;

  /// 펼칠 때 화면 안에 들어오는 카드 수. 그 아래 카드는 차례 없이 바로 보이는 상태다.
  int _visibleCards = 1 << 30;

  /// 섹션 머리 위 끝 ~ 이 위젯 위 끝 거리. 머리가 화면 밖이라 안 그려져 있을 때 머리 위치를 구하는 데 쓴다.
  double? _headerLead;

  @override
  void initState() {
    super.initState();
    final start = widget.open ? 1.0 : 0.0;
    _size = AnimationController(vsync: this, value: start);
    _fade = AnimationController(vsync: this, value: start);
  }

  @override
  void didUpdateWidget(RevealSection old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) widget.open ? _expand() : _shrink();
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    super.dispose();
  }

  int get _staggered => math.min(
    math.min(widget.cards.length, _visibleCards),
    AppReveal.maxStaggered,
  );

  /// 카드가 다 나오는 시각(ms)과 "접기"까지 다 나오는 전체 시각.
  int get _cardsEndMs =>
      math.max(0, _staggered - 1) * AppReveal.stagger.inMilliseconds +
      AppReveal.item.inMilliseconds;
  int get _openMs => _cardsEndMs + AppReveal.buttonFade.inMilliseconds;

  /// 이 위젯 위 끝의 화면(뷰포트) 위치와 스크롤 상태. 레이아웃 전이면 null.
  ({ScrollPosition position, double top, double offset})? _geometry() {
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (box == null || !box.attached || scrollable == null) return null;
    final position = scrollable.position;
    final offset = RenderAbstractViewport.of(box)
        .getOffsetToReveal(box, 0)
        .offset;
    return (position: position, top: offset - position.pixels, offset: offset);
  }

  /// 섹션 머리를 화면 맨 위에 둘 스크롤 위치. 머리가 안 그려져 있으면 마지막으로 잰 거리로 구한다.
  double? _headerTarget(double ownOffset) {
    final box = widget.header?.currentContext?.findRenderObject();
    if (box != null && box.attached) {
      final target = RenderAbstractViewport.of(box)
          .getOffsetToReveal(box, 0)
          .offset;
      _headerLead = ownOffset - target;
      return target;
    }
    final lead = _headerLead;
    return lead == null ? null : ownOffset - lead;
  }

  void _expand() {
    _closing = false;
    _capped = false;
    final g = _geometry();
    if (g != null) {
      _headerTarget(g.offset); // 머리가 보일 때 거리를 재 둔다(접을 때 머리가 멀어도 찾을 수 있게)
      final viewport = g.position.viewportDimension;
      _cap = (viewport - g.top).clamp(0.0, viewport);
    } else {
      _cap = double.infinity;
    }
    _visibleCards = 1 << 30;
    if (AppMotion.reduced(context)) {
      _size.value = 1;
      _fade.value = 1;
      return;
    }
    // 화면 안에 들어오는 카드 수는 카드가 그려진 뒤에 센다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _boxKey.currentContext?.findRenderObject();
      if (!mounted || box is! _RenderReveal || _closing) return;
      final count = box.childrenStartingBefore(_cap);
      if (count != _visibleCards) setState(() => _visibleCards = count);
    });
    _size.animateTo(1, duration: AppReveal.grow, curve: AppReveal.growCurve);
    final left = (_openMs * (1 - _fade.value)).round();
    _fade.animateTo(1, duration: Duration(milliseconds: math.max(1, left)));
  }

  /// "접기"를 눌렀을 때(부모가 상태를 바꾸기 전): 스크롤을 먼저 맞추고 줄일 구간을 정한다.
  /// 빌드 중에 스크롤을 옮기면 스크롤 알림이 빌드 중 setState가 되므로 여기(눌림 처리)에서 한다.
  void _onCollapseTap() {
    final g = _geometry();
    final box = _boxKey.currentContext?.findRenderObject();
    if (g != null && box is RenderBox && box.hasSize) {
      final p = g.position;
      final viewport = p.viewportDimension;
      final shown = box.size.height;
      final buttonY = g.top + shown; // 버튼 자리의 화면 위치
      final target = _headerTarget(g.offset);
      var top = g.top;
      if (target != null && target < p.pixels - 0.5) {
        if (AppMotion.reduced(context)) {
          p.jumpTo(target);
        } else {
          if (p.pixels - target >= viewport) {
            // 머리를 화면 0.5개 위까지 즉시 당기고, 줄어드는 높이로 버튼 자리를 그대로 둔다.
            final near = target + viewport * 0.5;
            top += p.pixels - near;
            p.jumpTo(near);
          }
          p.animateTo(
            target,
            duration: AppReveal.shrink,
            curve: AppReveal.shrinkCurve,
          );
        }
      }
      _cap = math.max(0, math.min(shown, buttonY - top));
      _capped = _cap < shown;
    }
    widget.onCollapse();
  }

  void _shrink() {
    if (!_closing) {
      _closing = true;
      _closeFrom = math.max(_fade.value, 0.001);
    }
    if (AppMotion.reduced(context)) {
      _size.value = 0;
      _fade.value = 0;
      return;
    }
    _size.animateTo(
      0,
      duration: AppReveal.shrink,
      curve: AppReveal.shrinkCurve,
    );
    _fade.animateTo(0, duration: AppReveal.fadeOut);
  }

  /// 펼치는 중 [i]번째 카드의 진행(0~1, 곡선 적용). [fade]는 시간축 값. 화면 밖 카드는 바로 1.
  double _itemAt(int i, double fade) {
    if (i >= _visibleCards) return 1;
    final t = fade * _openMs;
    final delay =
        math.min(i, AppReveal.maxStaggered - 1) *
        AppReveal.stagger.inMilliseconds;
    final local = ((t - delay) / AppReveal.item.inMilliseconds).clamp(0.0, 1.0);
    return AppReveal.itemCurve.transform(local);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_size, _fade]),
      builder: (context, _) {
        final fade = _fade.value;
        final hidden = !widget.open && _size.value == 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Reveal(
              key: _boxKey,
              progress: _size.value.clamp(0.0, 1.0),
              cap: _cap,
              capped: _capped,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hidden)
                    for (final (i, card) in widget.cards.indexed)
                      _item(i, card, fade),
                ],
              ),
            ),
            _button(fade),
          ],
        );
      },
    );
  }

  Widget _item(int i, Widget card, double fade) {
    final double opacity;
    final double dy;
    if (_closing) {
      // 그 순간 보이던 만큼에서 한꺼번에 줄어든다.
      opacity = _itemAt(i, _closeFrom) * (fade / _closeFrom).clamp(0.0, 1.0);
      dy = 0;
    } else {
      final p = _itemAt(i, fade);
      opacity = p;
      dy = AppReveal.shift * (1 - p);
    }
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: RepaintBoundary(child: card),
      ),
    );
  }

  /// 버튼 자리: 펼치는 중에는 "더 보기"가 먼저 사라지고, 카드가 다 나온 뒤 "접기"가 나타난다.
  /// 접는 중에는 "더 보기"가 다시 나타난다. 투명한 동안은 누를 수 없다.
  Widget _button(double fade) {
    final fadeMs = AppReveal.buttonFade.inMilliseconds;
    final Widget child;
    final double opacity;
    if (_closing || (!widget.open && _fade.value == 0)) {
      child = widget.more;
      opacity = _closing ? 1 - (fade / _closeFrom).clamp(0.0, 1.0) : 1;
    } else {
      final t = fade * _openMs;
      if (t < fadeMs) {
        child = widget.more;
        opacity = 1 - t / fadeMs;
      } else {
        child = widget.collapse(_onCollapseTap);
        opacity = ((t - _cardsEndMs) / fadeMs).clamp(0.0, 1.0);
      }
    }
    return IgnorePointer(
      ignoring: opacity == 0,
      child: ExcludeSemantics(
        excluding: opacity == 0,
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }
}

/// 진행([progress])만큼 아래를 잘라 보여 주는 상자. 진행이 1보다 작으면(또는 [capped]면) 움직이는 높이는
/// [cap]까지만이고, 다 펼치면 전체 높이다. 잘린 아래 부분은 그리지도, 누르지도 않는다.
class _Reveal extends SingleChildRenderObjectWidget {
  const _Reveal({
    super.key,
    required this.progress,
    required this.cap,
    required this.capped,
    super.child,
  });

  final double progress;
  final double cap;
  final bool capped;

  @override
  _RenderReveal createRenderObject(BuildContext context) =>
      _RenderReveal(progress, cap, capped);

  @override
  void updateRenderObject(BuildContext context, _RenderReveal renderObject) {
    renderObject
      ..progress = progress
      ..cap = cap
      ..capped = capped;
  }
}

class _RenderReveal extends RenderProxyBox {
  _RenderReveal(this._progress, this._cap, this._capped);

  double _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsLayout();
  }

  double _cap;
  set cap(double v) {
    if (v == _cap) return;
    _cap = v;
    markNeedsLayout();
  }

  bool _capped;
  set capped(bool v) {
    if (v == _capped) return;
    _capped = v;
    markNeedsLayout();
  }

  /// 위 끝이 [y]보다 위에 있는 자식(카드) 수.
  int childrenStartingBefore(double y) {
    final column = child;
    if (column is! RenderFlex) return 0;
    var count = 0;
    var c = column.firstChild;
    while (c != null) {
      final data = c.parentData! as FlexParentData;
      if (data.offset.dy >= y) break;
      count++;
      c = data.nextSibling;
    }
    return count;
  }

  @override
  void performLayout() {
    final c = child!;
    c.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final full = c.size.height;
    final double shown;
    if (_progress <= 0) {
      shown = 0;
    } else if (_capped || _progress < 1) {
      shown = math.min(full, _cap) * _progress;
    } else {
      shown = full;
    }
    size = constraints.constrain(Size(c.size.width, shown));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.height >= child!.size.height) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    if (size.height <= 0) {
      layer = null;
      return;
    }
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      oldLayer: layer as ClipRectLayer?,
    );
  }
}
