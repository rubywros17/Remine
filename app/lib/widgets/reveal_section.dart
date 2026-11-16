import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 섹션의 "더 보기"로 펼치는 부분: [cards](처음엔 숨은 카드들)과 그 아래 버튼 자리([more] ↔ [collapse]).
///
/// 펼치기: 높이가 부드럽게 늘고, 카드는 위에서부터 차례로 페이드 + 아래에서 올라온다. "더 보기"는 먼저 사라지고
/// "접기"는 마지막 카드가 다 나온 뒤 나타난다. 접기: 카드가 한꺼번에 사라지며 높이가 준다.
/// 값은 [AppReveal]. "애니메이션 줄이기"면 바로 바뀐다.
///
/// 열림 여부는 부모가 정하고([open]), 이 위젯은 그 사이를 움직이기만 한다. 움직이는 중에 [open]이 또 바뀌면
/// 지금 위치에서 새 목표로 이어서 간다(연타해도 꼬이지 않는다).
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
  });

  final bool open;
  final List<Widget> cards;
  final Widget more;
  final Widget collapse;

  @override
  State<RevealSection> createState() => _RevealSectionState();
}

class _RevealSectionState extends State<RevealSection>
    with TickerProviderStateMixin {
  /// 높이(0 = 접힘, 1 = 다 펼침). 곡선은 animateTo에서 준다.
  late final AnimationController _size;

  /// 카드·버튼 진행(펼칠 때는 차례로 나타나는 시간축, 접을 때는 한꺼번에 사라지는 정도).
  late final AnimationController _fade;

  bool _closing = false;

  /// 접기를 시작할 때의 [_fade] 값. 접는 동안 각 카드 투명도를 그 순간 값에서 비례해 줄인다.
  double _closeFrom = 1;

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

  int get _staggered => math.min(widget.cards.length, AppReveal.maxStaggered);

  /// 카드가 다 나오는 시각(ms)과 "접기"까지 다 나오는 전체 시각.
  int get _cardsEndMs =>
      math.max(0, _staggered - 1) * AppReveal.stagger.inMilliseconds +
      AppReveal.item.inMilliseconds;
  int get _openMs => _cardsEndMs + AppReveal.buttonFade.inMilliseconds;

  void _expand() {
    _closing = false;
    if (AppMotion.reduced(context)) {
      _size.value = 1;
      _fade.value = 1;
      return;
    }
    _size.animateTo(1, duration: AppReveal.grow, curve: AppReveal.growCurve);
    final left = (_openMs * (1 - _fade.value)).round();
    _fade.animateTo(1, duration: Duration(milliseconds: math.max(1, left)));
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

  /// 펼치는 중 [i]번째 카드의 진행(0~1, 곡선 적용). [fade]는 시간축 값.
  double _itemAt(int i, double fade) {
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
        final cards = <Widget>[
          if (!hidden)
            for (final (i, card) in widget.cards.indexed) _item(i, card, fade),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _size.value.clamp(0.0, 1.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards,
                ),
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
        child = widget.collapse;
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
