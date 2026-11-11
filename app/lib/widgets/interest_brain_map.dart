import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/interest.dart';
import 'app_button.dart';

/// 관심사 탭에 들어올 때마다 먼저 보여 주는 "머릿속 캡처 지도". 디자인 캔버스 19안 A.
///
/// 첫 진입: 왼쪽을 보는 옆얼굴 선 → 머릿속으로 확대(안쪽에 셀라돈 빛) → 뇌 윤곽 → 채움 → 소뇌·뇌간 → 주름
/// → 키워드 칩(1위부터) → 연결선(같은 캡처를 공유한 관심사) → 제목. 시간표는 [AppBrain].
/// 같은 앱 실행 중 두 번째 진입부터는 얼굴·확대를 건너뛰고 뇌 그리기부터 한다.
/// 그리는 중에 아무 데나 누르면 바로 마지막 상태, 다 그려진 뒤 누르면(또는 [목록 보기]) [onList].
/// "애니메이션 줄이기"면 마지막 상태를 바로 보여 준다.
///
/// [Flutter 메모] AnimationController는 0→1로 흐르는 시계, CustomPainter는 그 값으로 매 프레임 직접 그리는 캔버스다.
/// 여기서는 시계 값을 ms(지도 시작 기준)로 바꿔 각 단계 구간(예: 250~950ms)에 맞춘다.
class InterestBrainMap extends StatefulWidget {
  const InterestBrainMap({
    super.key,
    required this.interests,
    required this.onList,
  });

  /// 많이 캡처한 순. 앞에서 [AppBrain.maxNodes]개만 지도에 올린다.
  final List<Interest> interests;
  final VoidCallback onList;

  /// 같은 앱 실행 중 인트로(얼굴·확대)를 이미 보여 줬는지. 앱을 다시 켜면 처음부터.
  static bool _introSeen = false;

  @visibleForTesting
  static void resetIntro() => _introSeen = false;

  @override
  State<InterestBrainMap> createState() => _InterestBrainMapState();
}

class _InterestBrainMapState extends State<InterestBrainMap>
    with SingleTickerProviderStateMixin {
  late final List<BrainNode> _nodes = layoutNodes(widget.interests);
  late final int _totalMs = brainTotalMs(
    _nodes.length,
    brainLinks(_nodes).length,
  );
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs),
  );
  bool _intro = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1; // 마지막 상태
      return;
    }
    _intro = !InterestBrainMap._introSeen;
    InterestBrainMap._introSeen = true;
    _clock.forward(from: _intro ? 0 : AppBrain.brainStart / _totalMs);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_clock.isAnimating) {
      _clock.value = 1; // 건너뛰기: 바로 마지막 상태
    } else {
      widget.onList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes;
    final forgotten = nodes.where((n) => n.interest.forgotten).length;
    final textScaler = MediaQuery.textScalerOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: ColoredBox(
        color: AppColors.darkGray,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.s16 + AppBrain.titleDrop,
              AppSpacing.screenPadding,
              AppSpacing.s24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedBuilder(
                  animation: _clock,
                  builder: (context, child) {
                    final p = _span(_clock.value * _totalMs, (
                      AppBrain.titleStart,
                      AppBrain.titleStart + AppBrain.titleFade,
                    ), AppMotion.standard);
                    return Opacity(
                      opacity: p,
                      child: Transform.translate(
                        offset: Offset(0, AppBrain.titleRise * (1 - p)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '관심사',
                        style: AppText.title.copyWith(color: AppColors.white),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        '내 머릿속 캡처 지도',
                        style: AppText.caption.copyWith(
                          color: AppBrain.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                Expanded(
                  child: Semantics(
                    image: true,
                    label:
                        '머릿속 캡처 지도. 관심사 ${nodes.length}개'
                        '${forgotten > 0 ? ', 잊고 있던 것 $forgotten개' : ''}',
                    excludeSemantics: true,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final size = box.biggest;
                        final chips = layoutChips(nodes, size, textScaler);
                        return AnimatedBuilder(
                          animation: _clock,
                          builder: (context, _) => CustomPaint(
                            size: size,
                            painter: BrainPainter(
                              ms: _clock.value * _totalMs,
                              intro: _intro,
                              chips: chips,
                              textScaler: textScaler,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                Center(
                  child: AppButton(label: '목록 보기', onTap: widget.onList),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [ms]를 [range] 구간에서 0~1로 편다.
double _span(double ms, (int, int) range, [Curve curve = Curves.easeOut]) =>
    curve.transform(((ms - range.$1) / (range.$2 - range.$1)).clamp(0.0, 1.0));

/// 지도 전체 길이(ms): 제목·마지막 칩·마지막 연결선 중 가장 늦게 끝나는 때.
int brainTotalMs(int chipCount, int linkCount) => <int>[
  AppBrain.titleStart + AppBrain.titleFade,
  AppBrain.chipsStart +
      AppBrain.chipGap * (chipCount > 1 ? chipCount - 1 : 0) +
      AppBrain.chipPop,
  AppBrain.linksStart +
      AppBrain.linkGap * (linkCount > 1 ? linkCount - 1 : 0) +
      AppBrain.linkDraw,
].reduce(math.max);

/// 지도 위 관심사 하나: 뇌 그림 좌표(350×300)의 자리.
class BrainNode {
  const BrainNode(this.interest, this.slot, this.rank);

  final Interest interest;
  final Offset slot;

  /// 0이 가장 많이 캡처한 것(가장 먼저·가장 크게 떠오른다).
  final int rank;
}

// 시안의 자리(대뇌 안쪽). 앞쪽일수록 많이 캡처한 관심사가 앉는다.
const _slots = [
  Offset(150, 122),
  Offset(218, 92),
  Offset(206, 160),
  Offset(98, 168),
  Offset(262, 176),
  Offset(92, 104),
  Offset(268, 126),
];

/// 상위 [AppBrain.maxNodes]개를 자리에 앉힌다.
List<BrainNode> layoutNodes(List<Interest> interests) => [
  for (final (rank, interest)
      in interests.take(math.min(AppBrain.maxNodes, _slots.length)).indexed)
    BrainNode(interest, _slots[rank], rank),
];

/// 연결선 목록(같은 쌍은 한 번만): (앞 순위, 뒤 순위). 그리는 순서도 이 순서다.
List<(int, int)> brainLinks(List<BrainNode> nodes) {
  final rankOf = {for (final n in nodes) n.interest.tag: n.rank};
  final links = <(int, int)>{};
  for (final n in nodes) {
    for (final other in n.interest.linkedTags) {
      final m = rankOf[other];
      if (m == null || m == n.rank) continue;
      links.add((math.min(n.rank, m), math.max(n.rank, m)));
    }
  }
  return links.toList();
}

/// 시안 SVG 경로(M·Q·Z만)를 그대로 옮긴다.
Path _svg(String d) {
  final n = RegExp(r'-?\d+(\.\d+)?')
      .allMatches(d)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  final path = Path()..moveTo(n[0], n[1]);
  for (var i = 2; i + 3 < n.length; i += 4) {
    path.quadraticBezierTo(n[i], n[i + 1], n[i + 2], n[i + 3]);
  }
  if (d.trim().endsWith('Z')) path.close();
  return path;
}

final _cerebrum = _svg(
  'M74 206 Q42 204 44 176 Q20 156 38 130 Q26 102 56 88 Q58 58 92 56 '
  'Q106 30 138 38 Q160 18 188 32 Q214 18 240 36 Q270 32 280 60 Q308 66 306 96 '
  'Q330 116 312 142 Q328 168 302 182 Q300 208 270 210 Q252 228 226 216 '
  'Q204 230 182 216 Q160 230 136 218 Q110 228 96 212 Q84 218 74 206 Z',
);
final _cerebellum = _svg(
  'M186 206 Q226 200 258 206 Q268 220 250 230 Q226 238 202 232 Q188 226 186 206 Z',
);
final _brainstem = _svg(
  'M176 206 Q192 204 196 216 Q198 236 204 252 Q208 264 200 268 Q192 270 188 260 '
  'Q182 242 179 226 Q176 212 176 206 Z',
);
final _folds = [
  'M70 140 Q86 124 104 132 Q118 140 112 156',
  'M88 86 Q106 82 112 98 Q116 112 130 108',
  'M150 52 Q170 48 176 64 Q180 78 196 74',
  'M232 56 Q252 60 252 78 Q252 92 268 98',
  'M282 116 Q264 122 268 138 Q272 152 258 160',
  'M118 196 Q140 182 168 190 Q196 198 222 186 Q242 178 262 186',
  'M58 182 Q74 172 92 178',
  'M182 106 Q172 120 184 132',
].map(_svg).toList();

/// 뇌 전체(대뇌·소뇌·뇌간)를 감싸는 상자(뇌 좌표).
final _brainBox = _cerebrum
    .getBounds()
    .expandToInclude(_cerebellum.getBounds())
    .expandToInclude(_brainstem.getBounds());

/// 왼쪽을 보는 옆얼굴 선(뇌와 같은 좌표계). docs/design/brain_head.png(605×657)를 따라 찍은 점을
/// 뇌가 머리 안쪽 위에 앉도록 옮긴 것: 그림 (140, 70)이 뇌 좌표 (20, 18), 그림 1.16px이 뇌 1.
/// 점 사이는 부드러운 곡선(Catmull-Rom → 3차 베지어)으로 잇는다. 채움 없음.
final headPath = _smooth([
  for (final (x, y) in const [
    (195.0, 612.0),
    (193.0, 568.0),
    (178.0, 543.0),
    (140.0, 534.0),
    (95.0, 530.0),
    (68.0, 510.0),
    (62.0, 485.0),
    (64.0, 462.0),
    (56.0, 446.0),
    (53.0, 432.0),
    (50.0, 418.0),
    (48.0, 398.0),
    (45.0, 380.0),
    (30.0, 369.0),
    (14.0, 356.0),
    (14.0, 338.0),
    (35.0, 306.0),
    (58.0, 280.0),
    (67.0, 255.0),
    (65.0, 215.0),
    (69.0, 152.0),
    (100.0, 80.0),
    (176.0, 24.0),
    (285.0, 5.0),
    (400.0, 22.0),
    (481.0, 77.0),
    (526.0, 150.0),
    (542.0, 230.0),
    (530.0, 300.0),
    (500.0, 365.0),
    (472.0, 430.0),
    (460.0, 500.0),
    (465.0, 565.0),
    (480.0, 612.0),
  ])
    Offset((x - 140) / 1.16 + 20, (y - 70) / 1.16 + 18),
]);

Path _smooth(List<Offset> p) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = p[math.max(0, i - 1)];
    final p1 = p[i];
    final p2 = p[i + 1];
    final p3 = p[math.min(p.length - 1, i + 2)];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// 뇌 좌표 → 캔버스 좌표 변환: [focus](뇌 좌표)를 캔버스 가운데에 두고 [scale]배.
class BrainFrame {
  const BrainFrame(this.size, this.focus, this.scale);

  /// 마지막 상태: 뇌가 캔버스 너비(또는 높이)를 거의 채운다.
  factory BrainFrame.end(Size size) => BrainFrame(
    size,
    _brainBox.center,
    AppBrain.brainFill *
        math.min(size.width / _brainBox.width, size.height / _brainBox.height),
  );

  /// [z](0 얼굴 전체 → 1 마지막) 사이.
  factory BrainFrame.zoom(Size size, double z) {
    final end = BrainFrame.end(size);
    return BrainFrame(
      size,
      Offset.lerp(headPath.getBounds().center, end.focus, z)!,
      end.scale * (AppBrain.headStartScale + (1 - AppBrain.headStartScale) * z),
    );
  }

  final Size size;
  final Offset focus;
  final double scale;

  Offset toCanvas(Offset p) => size.center(Offset.zero) + (p - focus) * scale;
  Rect rectToCanvas(Rect r) =>
      Rect.fromPoints(toCanvas(r.topLeft), toCanvas(r.bottomRight));

  void apply(Canvas canvas) => canvas
    ..translate(size.width / 2, size.height / 2)
    ..scale(scale)
    ..translate(-focus.dx, -focus.dy);
}

/// 키워드 칩 하나(캔버스 좌표).
class BrainChip {
  const BrainChip(this.node, this.rect);

  final BrainNode node;
  final Rect rect;

  bool get top => node.rank == 0;
  Color get color =>
      top || node.interest.forgotten ? AppBrain.chipTop : AppBrain.chip;
  EdgeInsets get padding =>
      top ? AppBrain.chipTopPadding : AppBrain.chipPadding;
}

TextPainter _chipText(BrainNode n, double maxWidth, TextScaler scaler) =>
    TextPainter(
      text: TextSpan(
        text: n.interest.tag,
        style: AppText.label.copyWith(
          fontSize: n.rank == 0 ? AppBrain.chipTopFont : AppBrain.chipFont,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);

/// 칩을 먼저 가두는 영역: 마지막 상태의 대뇌 상자를 [_chipInset]만큼 줄인 것(캔버스 좌표, 캔버스 안으로 자름).
/// 대뇌는 둥근 모양이라 상자 모서리는 뇌 밖이다 → 안쪽으로 줄여 칩이 윤곽 밖으로 삐져나가 보이지 않게 한다.
const _chipInset = 16.0; // 뇌 좌표

Rect chipBrainBounds(Size size) =>
    BrainFrame.end(size)
        .rectToCanvas(_cerebrum.getBounds().deflate(_chipInset))
        .intersect(Offset.zero & size);

/// 칩 자리: 시안 자리에서 시작해 겹치는 칩끼리 밀어내고, 뇌 상자 안(안 되면 캔버스 안)에 가둔다.
/// 순위 순서로 돌려준다(뺀 칩은 없음).
/// 말줄임 없이 글자 길이만큼 늘어나고, 캔버스보다 길면 줄을 바꾼다.
List<BrainChip> layoutChips(
  List<BrainNode> nodes,
  Size size,
  TextScaler scaler,
) {
  if (nodes.isEmpty || size.isEmpty) return const [];
  final frame = BrainFrame.end(size);
  final canvasBox = Offset.zero & size;
  final brainBox = chipBrainBounds(size);
  final rects = [
    for (final n in nodes)
      () {
        final pad = n.rank == 0
            ? AppBrain.chipTopPadding
            : AppBrain.chipPadding;
        final text = _chipText(n, size.width - pad.horizontal, scaler);
        final s = Size(text.width + pad.horizontal, text.height + pad.vertical);
        text.dispose();
        return Rect.fromCenter(
          center: frame.toCanvas(n.slot),
          width: s.width,
          height: s.height,
        );
      }(),
  ];
  // 뇌 상자 안에서 먼저 풀어 보고, 자리가 모자라면 캔버스 전체로 넓힌다.
  // 그래도 안 되면(아주 작은 화면·큰 글자) 뒤 순위 칩부터 지도에서 뺀다(목록에는 그대로 있다).
  for (var n = rects.length; n > 0; n--) {
    for (final bounds in [brainBox, canvasBox]) {
      final tried = [for (final r in rects.take(n)) r];
      if (_relax(tried, bounds)) {
        return [for (final (i, r) in tried.indexed) BrainChip(nodes[i], r)];
      }
    }
  }
  return const [];
}

/// 겹친 칩을 덜 겹친 축으로 반씩 밀고 [bounds] 안에 가둔다. 다 풀리면 true.
/// ponytail: 칩 7개 × 수백 번이라 단순 반복으로 충분. 칩이 수십 개가 되면 격자 배치로 바꾼다.
bool _relax(List<Rect> rects, Rect bounds) {
  const gap = AppBrain.chipSpacing;
  for (var iter = 0; iter < 400; iter++) {
    var clean = true;
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final a = rects[i];
        final b = rects[j];
        final dx = math.min(a.right, b.right) - math.max(a.left, b.left) + gap;
        final dy = math.min(a.bottom, b.bottom) - math.max(a.top, b.top) + gap;
        if (dx <= _eps || dy <= _eps) continue; // 딱 간격만큼 떨어진 것은 겹침 아님(부동소수 오차)
        clean = false;
        final d = b.center - a.center;
        // 순위가 높은(앞) 칩은 덜 움직인다.
        const share = 0.35;
        final move = dx < dy
            ? Offset(d.dx >= 0 ? dx + _eps : -dx - _eps, 0)
            : Offset(0, d.dy >= 0 ? dy + _eps : -dy - _eps);
        rects[i] = a.shift(-move * share);
        rects[j] = b.shift(move * (1 - share));
      }
    }
    for (var i = 0; i < rects.length; i++) {
      rects[i] = _clampInto(rects[i], bounds);
    }
    if (clean) {
      // 칩 하나가 영역보다 크면 가둘 수 없다.
      return rects.every(
        (r) => r.width <= bounds.width && r.height <= bounds.height,
      );
    }
  }
  return false;
}

const _eps = 0.01;

Rect _clampInto(Rect r, Rect b) {
  double fit(double lo, double hi, double len, double at) =>
      len >= hi - lo ? (lo + hi - len) / 2 : at.clamp(lo, hi - len);
  return Offset(
        fit(b.left, b.right, r.width, r.left),
        fit(b.top, b.bottom, r.height, r.top),
      ) &
      r.size;
}

/// [ms](지도 시작 기준)에 맞춰 그린다. [intro]가 false면 얼굴·확대·빛 없이 마지막 크기에서 뇌부터.
class BrainPainter extends CustomPainter {
  BrainPainter({
    required this.ms,
    required this.intro,
    required this.chips,
    required this.textScaler,
  });

  final double ms;
  final bool intro;
  final List<BrainChip> chips;
  final TextScaler textScaler;

  double _phase((int, int) range, [Curve curve = Curves.easeOut]) =>
      _span(ms, range, curve);

  double _brainPhase((int, int) r, [Curve curve = Curves.easeOut]) =>
      _phase((AppBrain.brainStart + r.$1, AppBrain.brainStart + r.$2), curve);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = intro
        ? BrainFrame.zoom(size, _phase(AppBrain.zoom, AppBrain.zoomCurve))
        : BrainFrame.end(size);
    canvas.save();
    frame.apply(canvas);
    if (intro) _drawFace(canvas, frame.scale);
    _drawBrain(canvas);
    canvas.restore();

    _drawLinks(canvas);
    _drawChips(canvas);
  }

  void _drawFace(Canvas canvas, double scale) {
    // 머리 안쪽 빛: 나타났다 사라진다.
    final glow = math.sin(math.pi * _phase(AppBrain.glow, Curves.linear));
    if (glow > 0) {
      canvas.drawCircle(
        _brainBox.center,
        _brainBox.width * 0.42,
        Paint()
          ..color = AppColors.celadon.withValues(
            alpha: AppBrain.glowAlpha * glow,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    final face =
        _phase(AppBrain.faceIn, AppBrain.faceInCurve) *
        (1 - _phase(AppBrain.faceOut, AppBrain.faceOutCurve));
    if (face <= 0) return;
    canvas.drawPath(
      headPath,
      Paint()
        ..color = AppBrain.face.withValues(alpha: face)
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            AppBrain.faceStroke /
            scale // 화면에서 3px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ① 윤곽 → ② 안쪽 채움 → ③ 소뇌·뇌간(살짝 내려오며) → ④ 주름
  void _drawBrain(Canvas canvas) {
    final fill = _brainPhase(AppBrain.fillMs);
    final base = _brainPhase(AppBrain.baseMs);
    if (base > 0) {
      canvas
        ..save()
        ..translate(0, -6 * (1 - base));
      canvas.drawPath(
        _cerebellum,
        Paint()..color = AppBrain.cerebellum.withValues(alpha: base),
      );
      canvas.drawPath(
        _brainstem,
        Paint()..color = AppBrain.brainstem.withValues(alpha: base),
      );
      canvas.restore();
    }
    if (fill > 0) {
      canvas.drawPath(
        _cerebrum,
        Paint()..color = AppBrain.cerebrum.withValues(alpha: fill),
      );
    }
    _drawPartial(
      canvas,
      _cerebrum,
      _brainPhase(AppBrain.outlineMs, Curves.easeInOut),
      Paint()
        ..color = AppBrain.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round,
    );
    final foldPaint = Paint()
      ..color = AppBrain.fold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final f in _folds) {
      _drawPartial(canvas, f, _brainPhase(AppBrain.foldsMs), foldPaint);
    }
  }

  // 연결선은 칩 뒤에: 칩 가운데끼리, 하나씩 그려진다.
  void _drawLinks(Canvas canvas) {
    final paint = Paint()
      ..color = AppBrain.outline
      ..strokeWidth = AppBrain.linkStroke
      ..strokeCap = StrokeCap.round;
    final byRank = {for (final c in chips) c.node.rank: c.rect.center};
    for (final (i, (a, b)) in brainLinks([
      for (final c in chips) c.node,
    ]).indexed) {
      final start = AppBrain.linksStart + AppBrain.linkGap * i;
      final p = _phase((start, start + AppBrain.linkDraw), Curves.easeInOut);
      if (p <= 0) continue;
      canvas.drawLine(byRank[a]!, Offset.lerp(byRank[a], byRank[b], p)!, paint);
    }
  }

  void _drawChips(Canvas canvas) {
    for (final c in chips) {
      final start = AppBrain.chipsStart + AppBrain.chipGap * c.node.rank;
      final pop = _phase((start, start + AppBrain.chipPop), AppBrain.chipCurve);
      if (pop <= 0) continue;
      final alpha = _phase((start, start + AppBrain.chipPop ~/ 3))
          .clamp(0.0, 1.0);
      final scale = AppBrain.chipFromScale + (1 - AppBrain.chipFromScale) * pop;
      final rect = c.rect;
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.height / 2),
      );
      canvas
        ..save()
        ..translate(rect.center.dx, rect.center.dy)
        ..scale(scale)
        ..translate(-rect.center.dx, -rect.center.dy);
      const shadow = AppBrain.chipShadow;
      canvas.drawRRect(
        rrect.shift(shadow.offset),
        Paint()
          ..color = shadow.color.withValues(alpha: shadow.color.a * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = c.color.withValues(alpha: alpha),
      );
      final text = _chipText(
        c.node,
        rect.width - c.padding.horizontal,
        textScaler,
      );
      canvas.saveLayer(
        rect.inflate(2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
      text.paint(
        canvas,
        Offset(
          rect.center.dx - text.width / 2,
          rect.center.dy - text.height / 2,
        ),
      );
      canvas.restore();
      text.dispose();
      canvas.restore();
    }
  }

  void _drawPartial(Canvas canvas, Path path, double fraction, Paint paint) {
    if (fraction <= 0) return;
    for (final PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * fraction), paint);
    }
  }

  @override
  bool shouldRepaint(BrainPainter old) =>
      old.ms != ms ||
      old.intro != intro ||
      old.chips != chips ||
      old.textScaler != textScaler;
}
