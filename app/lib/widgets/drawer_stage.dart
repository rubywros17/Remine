import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/remote/sync_status.dart';
import '../models/category.dart';
import 'capture_thumb.dart';

/// 첫 분석 화면 가운데: 방금 분류된 캡처 카드가 나타났다가 7개 서랍 칸 중 자기 칸으로 들어간다.
///
/// - [status]의 분류 기록을 큐에 넣고 [drawerGap] 간격으로 한 장씩 꺼낸다(다음 묶음이 올 때까지 고르게). 카드가
///   [AnalysisStage.maxCards]장 떠 있으면 그 장은 카드 없이 칸만 +1 한다(링은 울린다).
/// - 실행 중에는 다음에 나올 캡처(큐, 없으면 지금 서버에 보낸 묶음)를 겹친 카드로 보여 주고 맨 앞에 스캔 선이 지나간다([DrawerCardStack]).
///   결과가 오면 맨 앞 카드가 이름표를 받고 날아가고 뒤 카드가 앞으로 당겨진다. 보여 줄 썸네일이 없으면 빈 카드가 숨 쉰다.
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
    this.finished = false,
  });

  /// 칸을 다 채웠는지. 그러면 카드 자리까지 칸이 자란다.
  final bool finished;

  /// [status]가 없을 때(개발용 가짜 값) 칸에 보여 줄 개수.
  final Map<Category, int> counts;
  final SyncStatus? status;
  final void Function(int landed, bool settled)? onProgress;

  @override
  State<DrawerStage> createState() => _DrawerStageState();
}

/// 다음 카드까지의 간격. 분석이 끝났으면 빠르게 채우고, 큐가 밀렸으면 줄이고, 그 외에는 다음 묶음까지 남은 시간을 나눈다.
Duration drawerGap({
  required int queue,
  required Duration? untilNextBatch,
  required bool draining,
}) {
  if (draining) return AnalysisStage.drainGap;
  if (queue > AnalysisStage.fastQueue) return AnalysisStage.fastGap;
  if (untilNextBatch == null || queue <= 0) return AnalysisStage.gap;
  final ms = (untilNextBatch.inMilliseconds / queue).round().clamp(
    AnalysisStage.gap.inMilliseconds,
    AnalysisStage.maxGap.inMilliseconds,
  );
  return Duration(milliseconds: ms);
}

/// 비행 진행도(곡선 적용 후)에 따른 불투명도. 칸 숫자에 닿기 전에 완전히 사라진다.
double flightOpacity(double progress) =>
    1 - const Interval(0.6, 0.85).transform(progress);

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
  String? _shownFront; // 지금 묶음 맨 앞에 보이는 캡처. 이 캡처의 카드는 제자리에서 이름표를 받는다

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
    for (var i = _seen; i < shots.length; i++) {
      final shot = shots[i];
      if (shot.assetId == null || _reduced) {
        _shown.update(shot.category, (n) => n + 1, ifAbsent: () => 1);
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
    setState(() {}); // 칸 숫자·대기 카드 표시
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
    final wait = drawerGap(
      queue: _queue.length,
      untilNextBatch: widget.status?.untilNextBatch,
      draining: _draining,
    );
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
    final fromStack = shot.assetId == _shownFront;
    final flight = _Flight(
      id,
      shot,
      fromStack
          ? AnalysisStage.stackFrontTilt
          : id.isEven
          ? -AnalysisStage.tiltRadians
          : AnalysisStage.tiltRadians,
      this,
    );
    flight.enter.addStatusListener((s) {
      if (s == AnimationStatus.completed) flight.fly.forward();
    });
    flight.fly.addStatusListener((s) {
      if (s == AnimationStatus.completed) _land(flight);
    });
    setState(() => _cards.add(flight));
    // 이미 맨 앞에 보이던 카드는 등장을 건너뛰고 이름표부터.
    flight.enter.forward(from: fromStack ? DrawerFlightCard.appearEnd : 0);
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

  /// 묶음에 보여 줄 캡처. 큐가 먼저고(다음에 날아갈 순서), 없으면 지금 서버에 보낸 묶음.
  List<String> _stackIds() {
    final status = widget.status;
    if (status == null || !status.running) return const [];
    final queued = [
      for (final s in _queue.take(SyncStatus.maxFaces)) s.assetId!,
    ];
    return queued.isNotEmpty ? queued : status.batchFaces;
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
    final finished = widget.finished;
    final binsHeight = finished
        ? height
        : (height * AnalysisStage.binsShare).clamp(
            AnalysisStage.binsMinHeight,
            AnalysisStage.binsMaxHeight,
          );
    final zoneHeight = height - binsHeight;
    final maxCardWidth = width * AnalysisStage.cardMaxWidthShare;
    final tallCardWidth =
        zoneHeight * AnalysisStage.cardShare / AnalysisStage.cardAspect;
    final cardWidth = tallCardWidth < maxCardWidth
        ? tallCardWidth
        : maxCardWidth;
    final cardSize = Size(cardWidth, cardWidth * AnalysisStage.cardAspect);
    // 가장 많이 기울어진 카드까지 포함한 높이. 이 안에 들어가게 놓아 위 문구·아래 칸 숫자와 겹치지 않는다.
    final tiltedHeight =
        cardSize.height * math.cos(AnalysisStage.tiltRadians) +
        cardSize.width * math.sin(AnalysisStage.tiltRadians);
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

    // 처음 몇 장은 칸이 곧장 꽉 차지 않게, binFullAt장까지는 같은 비율로 자란다. 끝나면 최대값이 남는 공간을 다 쓴다.
    final most = _shown.values.fold(
      finished ? 1 : AnalysisStage.binFullAt,
      _max,
    );
    double barHeight(Category c) =>
        AnalysisStage.binStub +
        (barMax - AnalysisStage.binStub) * ((_shown[c] ?? 0) / most);

    // 기울어진 카드의 아래 끝을 칸 영역 위에 붙인다.
    final from = Offset(width / 2, zoneHeight - tiltedHeight / 2);
    // 등장은 위에서 내려오지만 스테이지 위로는 나가지 않는다(낮은 화면에서 문구를 덮지 않게).
    final appearFrom = -math.min(
      -AnalysisStage.appearOffsetY,
      math.max(0.0, zoneHeight - tiltedHeight),
    );
    // 숫자 위까지만 날아간다. 축소된 카드의 아래 끝이 숫자에 닿지 않는 자리.
    Offset target(Category c) => Offset(
      (c.index + 0.5) * cellWidth + c.index * AnalysisStage.binGap,
      height -
          AnalysisStage.labelHeight -
          AnalysisStage.binGap * 2 -
          barHeight(c) -
          AnalysisStage.numberHeight -
          cardSize.height * AnalysisStage.flyEndScale / 2,
    );
    final cardLeft = from.dx - cardSize.width / 2;
    final cardTop = from.dy - cardSize.height / 2;
    final stackIds = _stackIds();
    _shownFront = stackIds.isEmpty ? null : stackIds.first;
    final idle =
        widget.status?.running == true && stackIds.isEmpty && _cards.isEmpty;

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
                    finished: finished,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (stackIds.isNotEmpty)
          Positioned(
            left: cardLeft,
            top: cardTop,
            width: cardSize.width,
            height: cardSize.height,
            child: DrawerCardStack(assetIds: stackIds, reduced: _reduced),
          ),
        if (idle)
          Positioned(
            left: cardLeft,
            top: cardTop,
            width: cardSize.width,
            height: cardSize.height,
            child: _BreathingCard(reduced: _reduced),
          ),
        for (final card in _cards)
          Positioned(
            key: ValueKey(card.id),
            left: cardLeft,
            top: cardTop,
            width: cardSize.width,
            height: cardSize.height,
            child: DrawerFlightCard(
              shot: card.shot,
              enter: card.enter,
              fly: card.fly,
              tilt: card.tilt,
              travel: target(card.shot.category) - from,
              appearFrom: appearFrom,
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
    this.appearFrom = AnalysisStage.appearOffsetY,
  });

  /// [enter]에서 등장이 끝나는 지점. 여기부터 이름표가 나온다.
  static final double appearEnd =
      AnalysisStage.appear.inMilliseconds / _Flight._enterTotal.inMilliseconds;
  static final double _popEnd =
      (AnalysisStage.appear + AnalysisStage.tagPop).inMilliseconds /
      _Flight._enterTotal.inMilliseconds;

  final ClassifiedShot shot;
  final Animation<double> enter;
  final Animation<double> fly;
  final double tilt;
  final Offset travel;
  final double appearFrom;

  @override
  Widget build(BuildContext context) {
    final appear = Interval(0, appearEnd, curve: AppMotion.standard);
    final pop = enter.drive(
      CurveTween(
        curve: Interval(appearEnd, _popEnd, curve: Curves.easeOutBack),
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
                key: const ValueKey('flight-tag'),
                decoration: BoxDecoration(
                  color: AppCategoryColors.of(shot.category),
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
        final y = lerpDouble(appearFrom, 0, t)!;
        final scale =
            lerpDouble(AnalysisStage.appearScale, 1, t)! *
            lerpDouble(1, AnalysisStage.flyEndScale, f)!;
        final opacity = (t * flightOpacity(f)).clamp(0.0, 1.0);
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

/// 대기 묶음: 맨 앞 카드 + 좌우로 비켜 기운 뒤 카드 2장. 장이 빠지면 뒤 카드가 앞으로 당겨진다.
class DrawerCardStack extends StatelessWidget {
  const DrawerCardStack({
    super.key,
    required this.assetIds,
    required this.reduced,
  });

  /// 맨 앞부터.
  final List<String> assetIds;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        for (var slot = assetIds.length - 1; slot >= 0; slot--)
          _StackCard(
            key: ValueKey(assetIds[slot]),
            assetId: assetIds[slot],
            slot: slot,
            reduced: reduced,
          ),
      ],
    );
  }
}

class _StackCard extends StatelessWidget {
  const _StackCard({
    super.key,
    required this.assetId,
    required this.slot,
    required this.reduced,
  });

  final String assetId;
  final int slot; // 0이 맨 앞
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final front = slot == 0;
    final duration = AppMotion.duration(context, MotionDuration.base);
    final side = slot == 1 ? 1.0 : -1.0;
    final tilt = front
        ? AnalysisStage.stackFrontTilt
        : side * AnalysisStage.tiltRadians;
    // [Flutter 메모] 값이 바뀌면 알아서 보간하는 암시적 애니메이션. key가 같으니 자리만 옮겨 다니고 썸네일은 다시 읽지 않는다.
    return AnimatedSlide(
      offset: Offset(front ? 0 : side * AnalysisStage.stackBackOffset, 0),
      duration: duration,
      curve: AppMotion.standard,
      child: AnimatedRotation(
        turns: tilt / (2 * math.pi),
        duration: duration,
        curve: AppMotion.standard,
        child: AnimatedScale(
          scale: front ? 1 : AnalysisStage.stackBackScale,
          duration: duration,
          curve: AppMotion.standard,
          child: AnimatedOpacity(
            opacity: front ? 1 : AnalysisStage.stackBackOpacity,
            duration: duration,
            child: CaptureThumb(
              assetId: assetId,
              seed: assetId.hashCode.abs(),
              radius: AppRadii.tile,
              size: 240,
              child: front && !reduced
                  ? const Positioned.fill(child: _ScanLine())
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 맨 앞 카드 위를 왕복하는 셀라돈 선. 주변은 옅은 글로우, 위쪽은 아주 옅은 그라데이션.
class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: AnalysisStage.scanHalf,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.tile),
      child: LayoutBuilder(
        builder: (context, box) {
          final travel = box.maxHeight - AnalysisStage.scanLineHeight;
          final trail = box.maxHeight * AnalysisStage.scanTrailShare;
          return AnimatedBuilder(
            animation: _scan,
            builder: (context, _) {
              final y = travel * _scan.value;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: y - trail,
                    height: trail,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.celadon.withValues(alpha: 0),
                            AppColors.celadon.withValues(
                              alpha: AnalysisStage.scanTrailOpacity,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('scan-line'),
                    left: 0,
                    right: 0,
                    top: y,
                    height: AnalysisStage.scanLineHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.celadon,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.celadon.withValues(alpha: 0.6),
                            blurRadius: AnalysisStage.scanGlowBlur,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 보여 줄 썸네일이 없을 때 카드 자리에 놓이는 빈 카드. 다음 묶음을 기다리는 동안 은은하게 숨 쉰다.
class DrawerIdleCard extends StatelessWidget {
  const DrawerIdleCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
    );
  }
}

class _BreathingCard extends StatefulWidget {
  const _BreathingCard({required this.reduced});

  final bool reduced;

  @override
  State<_BreathingCard> createState() => _BreathingCardState();
}

class _BreathingCardState extends State<_BreathingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: AnalysisStage.breathHalf,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_BreathingCard old) {
    super.didUpdateWidget(old);
    if (old.reduced != widget.reduced) _sync();
  }

  void _sync() {
    if (widget.reduced) {
      _breath.value = 1;
    } else {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _breath.drive(
        Tween(
          begin: AnalysisStage.breathScale,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: const DrawerIdleCard(),
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
    required this.finished,
  });

  final bool finished;
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
          duration: widget.reduced
              ? Duration.zero
              : widget.finished
              ? AnalysisStage.binGrow
              : AnalysisStage.binSpring,
          curve: Curves.easeOutBack,
          // 위쪽 상한: 칸 영역이 줄면(완료 요약이 늦게 들어올 때) 옛 높이에서 내려오는 동안 넘치지 않게 한다.
          builder: (context, height, _) => SizedBox(
            height: height.clamp(0, widget.barHeight * AnalysisStage.overshoot),
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
