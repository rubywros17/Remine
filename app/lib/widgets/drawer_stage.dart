import 'dart:async';
import 'dart:collection';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/remote/sync_status.dart';
import '../models/category.dart';
import 'capture_thumb.dart';

/// 첫 분석 화면 가운데: 방금 분류된 캡처 카드가 나타났다가 7개 서랍 칸 중 자기 칸으로 들어간다.
///
/// - [status]의 분류 기록을 큐에 넣고 [AnalysisStage.gap] 간격으로 한 장씩 꺼낸다. 카드가 [AnalysisStage.maxCards]장 떠 있으면
///   그 장은 카드 없이 칸만 +1 한다(링은 울린다).
/// - 분석이 끝나면 남은 큐를 [AnalysisStage.drainGap] 간격으로 카드 없이 채운다.
/// - 숨김 캡처(썸네일 없음)와 모션 줄이기 설정에서는 카드·링 없이 칸과 숫자만 바로 갱신한다.
/// - 칸 합계와 "다 채웠는지"를 [onProgress]로 알린다. 화면의 큰 숫자는 이 값을 쓴다.
/// - 부모가 준 높이를 전부 쓰고, 그 안에서 칸·카드 크기를 계산한다.
class DrawerStage extends StatefulWidget {
  const DrawerStage({
    super.key,
    required this.counts,
    this.status,
    this.onProgress,
  });

  /// [status]가 없을 때(개발용 가짜 값) 칸에 보여 줄 개수.
  final Map<Category, int> counts;
  final SyncStatus? status;
  final void Function(int landed, bool settled)? onProgress;

  @override
  State<DrawerStage> createState() => _DrawerStageState();
}

/// 칸 아래 이름. 7칸이 좁아 이 화면에서만 두 글자로 줄인다(다른 화면과 카드 이름표는 [Category.label]).
String drawerBinLabel(Category c) =>
    c == Category.entertainment ? '문화' : c.label;

class _Flight {
  _Flight(this.id, this.shot, this.tilt, TickerProvider vsync)
    : enter = AnimationController(vsync: vsync, duration: _enterTotal),
      fly = AnimationController(vsync: vsync, duration: AnalysisStage.fly);

  static final _enterTotal =
      AnalysisStage.appear + AnalysisStage.tagPop + AnalysisStage.hold;

  final int id;
  final ClassifiedShot shot;
  final double tilt;
  final AnimationController enter; // 등장 + 이름표 + 멈춤
  final AnimationController fly;

  void dispose() {
    enter.dispose();
    fly.dispose();
  }
}

// [Flutter 메모] TickerProviderStateMixin은 AnimationController를 여러 개 만들 수 있게 화면 주사율 신호(vsync)를 준다.
class _DrawerStageState extends State<DrawerStage>
    with TickerProviderStateMixin {
  final Map<Category, int> _shown = {};
  final Map<Category, int> _landings = {}; // 칸마다 링을 울린 횟수
  final Queue<ClassifiedShot> _queue = Queue();
  final List<_Flight> _cards = [];

  int _runId = 0;
  int _seen = 0;
  int _nextId = 0;
  Timer? _gap;
  bool _draining = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    final status = widget.status;
    // 진행 중에 열어도 이미 분류된 것은 다시 날리지 않는다.
    _shown.addAll(status?.counts ?? widget.counts);
    _runId = status?.runId ?? 0;
    _seen = status?.shots.length ?? 0;
    _draining = status?.finished ?? false;
    status?.addListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
  }

  void _onStatus() {
    final status = widget.status!;
    if (status.runId != _runId) _reset(status.runId);
    final shots = status.shots;
    var bumped = false;
    for (var i = _seen; i < shots.length; i++) {
      final shot = shots[i];
      if (shot.assetId == null || _reduced) {
        _shown.update(shot.category, (n) => n + 1, ifAbsent: () => 1);
        bumped = true;
      } else {
        _queue.add(shot);
      }
    }
    _seen = shots.length;
    if (status.finished && !_draining) {
      _gap?.cancel(); // 지금 기다리는 간격을 버리고 바로 채우기 시작한다
      _gap = null;
    }
    _draining = status.finished;
    if (bumped) setState(() {});
    _next();
    _report();
  }

  void _reset(int runId) {
    _gap?.cancel();
    _gap = null;
    _queue.clear();
    for (final c in _cards) {
      c.dispose();
    }
    _cards.clear();
    _runId = runId;
    _seen = 0;
    _shown.clear();
    setState(() {});
  }

  void _next() {
    if (_gap != null || _queue.isEmpty) return;
    final wait = _draining
        ? AnalysisStage.drainGap
        : _queue.length > AnalysisStage.fastQueue
        ? AnalysisStage.fastGap
        : AnalysisStage.gap;
    final shot = _queue.removeFirst();
    if (_draining || _cards.length >= AnalysisStage.maxCards) {
      _bump(shot.category);
    } else {
      _launch(shot);
    }
    _gap = Timer(wait, () {
      _gap = null;
      _next();
    });
  }

  void _launch(ClassifiedShot shot) {
    final id = _nextId++;
    final flight = _Flight(
      id,
      shot,
      id.isEven ? -AnalysisStage.tiltRadians : AnalysisStage.tiltRadians,
      this,
    );
    flight.enter.addStatusListener((s) {
      if (s == AnimationStatus.completed) flight.fly.forward();
    });
    flight.fly.addStatusListener((s) {
      if (s == AnimationStatus.completed) _land(flight);
    });
    setState(() => _cards.add(flight));
    flight.enter.forward();
  }

  void _land(_Flight flight) {
    _cards.remove(flight);
    _bump(flight.shot.category);
    // 이 콜백은 컨트롤러 안에서 불리고 카드 위젯도 아직 트리에 있으므로, 빠진 다음 프레임에 정리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => flight.dispose());
  }

  /// 칸 +1 + 링 한 번.
  void _bump(Category category) {
    setState(() {
      _shown.update(category, (n) => n + 1, ifAbsent: () => 1);
      _landings.update(category, (n) => n + 1, ifAbsent: () => 1);
    });
    _report();
  }

  void _report() {
    final status = widget.status;
    if (status == null) return;
    widget.onProgress?.call(
      _shown.values.fold(0, (a, b) => a + b),
      status.finished && _queue.isEmpty && _cards.isEmpty,
    );
  }

  @override
  void dispose() {
    widget.status?.removeListener(_onStatus);
    _gap?.cancel();
    for (final c in _cards) {
      c.dispose();
    }
    super.dispose();
  }

  String get _semanticLabel {
    final parts = [
      for (final c in Category.values) '${c.label} ${_shown[c] ?? 0}장',
    ];
    return '지금까지 찾은 것: ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    // [Flutter 메모] 부모(IntrinsicHeight)가 내용 높이를 물어볼 때 LayoutBuilder는 답하지 못해 오류가 난다.
    // Positioned 자식은 Stack의 높이 계산에서 빠지므로, 최소 높이만 답하고 실제 높이는 부모 Expanded에서 받는다.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AnalysisStage.minHeight),
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: _semanticLabel,
              excludeSemantics: true,
              child: LayoutBuilder(builder: _buildStage),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context, BoxConstraints box) {
    final width = box.maxWidth;
    final height = box.maxHeight;
    final binsHeight = height * AnalysisStage.binsShare;
    final zoneHeight = height - binsHeight;
    final cardHeight = (zoneHeight * 0.88).clamp(
      0.0,
      AnalysisStage.cardMaxHeight,
    );
    final cardSize = Size(cardHeight / AnalysisStage.cardAspect, cardHeight);
    final cellWidth =
        (width - AnalysisStage.binGap * (Category.values.length - 1)) /
        Category.values.length;
    final barMax =
        ((binsHeight -
                    AnalysisStage.numberHeight -
                    AnalysisStage.labelHeight -
                    AnalysisStage.binGap * 2) /
                AnalysisStage.overshoot)
            .clamp(AnalysisStage.binStub, double.infinity);

    // 처음 몇 장은 칸이 곧장 꽉 차지 않게, binFullAt장까지는 같은 비율로 자란다.
    final most = _shown.values.fold(AnalysisStage.binFullAt, _max);
    double barHeight(Category c) =>
        AnalysisStage.binStub +
        (barMax - AnalysisStage.binStub) * ((_shown[c] ?? 0) / most);

    final from = Offset(width / 2, zoneHeight / 2);
    Offset target(Category c) => Offset(
      (c.index + 0.5) * cellWidth + c.index * AnalysisStage.binGap,
      height - AnalysisStage.labelHeight - AnalysisStage.binGap - barHeight(c),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: binsHeight,
          // 칸은 바닥을 맞추고 위로 자란다. 이름표는 칸 아래 같은 높이에 놓인다.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final c in Category.values) ...[
                if (c.index > 0) const SizedBox(width: AnalysisStage.binGap),
                Expanded(
                  child: _Bin(
                    category: c,
                    count: _shown[c] ?? 0,
                    barHeight: barHeight(c),
                    landings: _landings[c] ?? 0,
                    reduced: _reduced,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final card in _cards)
          Positioned(
            key: ValueKey(card.id),
            left: from.dx - cardSize.width / 2,
            top: from.dy - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height,
            child: DrawerFlightCard(
              shot: card.shot,
              enter: card.enter,
              fly: card.fly,
              tilt: card.tilt,
              travel: target(card.shot.category) - from,
            ),
          ),
      ],
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
}

/// 날아가는 카드 한 장: 실제 썸네일 + 카테고리 이름표. [travel]은 출발점에서 칸까지의 거리.
class DrawerFlightCard extends StatelessWidget {
  const DrawerFlightCard({
    super.key,
    required this.shot,
    required this.enter,
    required this.fly,
    required this.tilt,
    required this.travel,
  });

  static final double _appearEnd =
      AnalysisStage.appear.inMilliseconds / _Flight._enterTotal.inMilliseconds;
  static final double _popEnd =
      (AnalysisStage.appear + AnalysisStage.tagPop).inMilliseconds /
      _Flight._enterTotal.inMilliseconds;

  final ClassifiedShot shot;
  final Animation<double> enter;
  final Animation<double> fly;
  final double tilt;
  final Offset travel;

  @override
  Widget build(BuildContext context) {
    final appear = Interval(0, _appearEnd, curve: AppMotion.standard);
    final pop = enter.drive(
      CurveTween(
        curve: Interval(_appearEnd, _popEnd, curve: Curves.easeOutBack),
      ),
    );
    final assetId = shot.assetId!;
    return AnimatedBuilder(
      animation: Listenable.merge([enter, fly]),
      // [Flutter 메모] child는 한 번만 만들어 프레임마다 재사용한다. 썸네일을 다시 읽지 않는다.
      child: CaptureThumb(
        assetId: assetId,
        seed: assetId.hashCode.abs(),
        radius: AppRadii.tile,
        size: 240,
        child: Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: ScaleTransition(
            scale: pop,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.lemon,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    shot.category.label,
                    style: AppText.label.copyWith(fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, child) {
        final t = appear.transform(enter.value);
        final f = AppMotion.exit.transform(fly.value);
        // 곡선 경로(2차 베지어): 옆으로 나갔다가 칸으로 떨어진다. 제어점은 칸의 x, 출발점의 y.
        final dx = travel.dx * (2 * (1 - f) * f + f * f);
        final dy = travel.dy * f * f;
        final y = lerpDouble(AnalysisStage.appearOffsetY, 0, t)!;
        final scale =
            lerpDouble(AnalysisStage.appearScale, 1, t)! *
            lerpDouble(1, AnalysisStage.flyEndScale, f)!;
        final opacity = (t * (1 - const Interval(0.6, 1).transform(f))).clamp(
          0.0,
          1.0,
        );
        return Transform.translate(
          offset: Offset(dx, y + dy),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(
              scale: scale,
              child: Opacity(opacity: opacity, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// 서랍 한 칸: 위부터 숫자 · 막대 · 이름표. 막대 높이는 스프링으로 바뀌고, 한 장이 들어오면 같은 색 링이 한 번 퍼진다.
class _Bin extends StatefulWidget {
  const _Bin({
    required this.category,
    required this.count,
    required this.barHeight,
    required this.landings,
    required this.reduced,
  });

  final Category category;
  final int count;
  final double barHeight;
  final int landings;
  final bool reduced;

  @override
  State<_Bin> createState() => _BinState();
}

class _BinState extends State<_Bin> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: AnalysisStage.binSpring,
    value: 1, // 시작할 때는 링이 보이지 않는다
  );

  @override
  void didUpdateWidget(_Bin old) {
    super.didUpdateWidget(old);
    if (widget.landings > old.landings && !widget.reduced) {
      _ring.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppCategoryColors.of(widget.category);
    final radius = BorderRadius.circular(AnalysisStage.binRadius);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: AnalysisStage.numberHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${widget.count}',
              style: AppText.numBadge(color: AppColors.white),
            ),
          ),
        ),
        const SizedBox(height: AnalysisStage.binGap),
        TweenAnimationBuilder<double>(
          tween: Tween(end: widget.barHeight),
          duration: widget.reduced ? Duration.zero : AnalysisStage.binSpring,
          curve: Curves.easeOutBack,
          builder: (context, height, _) => SizedBox(
            height: height < 0 ? 0 : height,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: radius),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _ring,
                    builder: (context, _) => _ring.isCompleted
                        ? const SizedBox.shrink()
                        : Opacity(
                            opacity: 1 - _ring.value,
                            child: Transform.scale(
                              scale: lerpDouble(
                                1,
                                AnalysisStage.ringScale,
                                _ring.value,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  border: Border.all(
                                    color: color,
                                    width: AnalysisStage.ringWidth,
                                  ),
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
        const SizedBox(height: AnalysisStage.binGap),
        SizedBox(
          height: AnalysisStage.labelHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              drawerBinLabel(widget.category),
              maxLines: 1,
              style: AppText.caption.copyWith(
                fontSize: AnalysisStage.labelSize,
                color: AppColors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
