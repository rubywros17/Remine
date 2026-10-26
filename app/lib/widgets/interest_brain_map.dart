import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/interest.dart';

/// 관심사 탭에 처음 들어올 때 한 번 보여 주는 "머릿속 캡처 지도"(약 3초). 디자인 캔버스 4안의 뇌 그림을 옮겼다.
///
/// 순서: 뇌 윤곽 → 안쪽 채움 → 소뇌·뇌간 → 주름 → 관심사 원(많이 캡처할수록 큼) → 연결선(같은 캡처를 공유한 관심사)
/// → 잊은 관심사(마지막 캡처 [Interest.forgottenAfterDays]일 이상)가 레몬색으로 깨어남. 끝나거나 화면을 누르면 [onDone].
///
/// [Flutter 메모] AnimationController는 0→1로 흐르는 시계, CustomPainter는 그 값(t)으로 매 프레임 직접 그리는 캔버스다.
/// 각 단계는 t의 구간(예: 0~0.17)을 0~1로 다시 펴서 쓴다(Interval).
class InterestBrainMap extends StatefulWidget {
  const InterestBrainMap({
    super.key,
    required this.interests,
    required this.onDone,
  });

  /// 많이 캡처한 순. 앞에서 [AppBrain.maxNodes]개만 지도에 올린다.
  final List<Interest> interests;
  final VoidCallback onDone;

  @override
  State<InterestBrainMap> createState() => _InterestBrainMapState();
}

class _InterestBrainMapState extends State<InterestBrainMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: AppBrain.duration,
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _clock
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = layoutNodes(widget.interests);
    final forgotten = nodes.where((n) => n.interest.forgotten).length;
    return Semantics(
      button: true,
      label:
          '머릿속 캡처 지도. 관심사 ${nodes.length}개'
          '${forgotten > 0 ? ', 잊고 있던 것 $forgotten개' : ''}. 누르면 목록으로 넘어가요',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish, // 아무 데나 누르면 건너뛰기
        child: ColoredBox(
          color: AppColors.darkGray,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.s16,
                AppSpacing.screenPadding,
                AppSpacing.s24,
              ),
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
                    style: AppText.caption.copyWith(color: AppBrain.subtitle),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _clock,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: BrainPainter(t: _clock.value, nodes: nodes),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 위 관심사 원 하나(뇌 그림 좌표 350×300 기준).
class BrainNode {
  const BrainNode(this.interest, this.center, this.radius, this.rank);

  final Interest interest;
  final Offset center;
  final double radius;

  /// 0이 가장 많이 캡처한 것(가장 먼저·가장 크게 떠오른다).
  final int rank;
}

// 시안의 원 자리(대뇌 안쪽). 앞쪽일수록 많이 캡처한 관심사가 앉는다.
const _slots = [
  Offset(150, 122),
  Offset(218, 92),
  Offset(206, 160),
  Offset(98, 168),
  Offset(262, 176),
  Offset(92, 104),
  Offset(268, 126),
];

/// 상위 [AppBrain.maxNodes]개를 자리에 앉히고, 캡처 횟수 비율로 반지름을 정한다(1위만 크게, 나머지는 겹치지 않게 작게).
List<BrainNode> layoutNodes(List<Interest> interests) {
  final shown = interests
      .take(math.min(AppBrain.maxNodes, _slots.length))
      .toList();
  if (shown.isEmpty) return const [];
  final counts = shown.map((i) => i.captureCount);
  final most = counts.reduce(math.max);
  final least = counts.reduce(math.min);
  return [
    for (final (rank, interest) in shown.indexed)
      BrainNode(
        interest,
        _slots[rank],
        rank == 0
            ? 36
            : 15 +
                  9 *
                      (most == least
                          ? 0.5
                          : (interest.captureCount - least) / (most - least)),
        rank,
      ),
  ];
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

/// [t](0~1)에 맞춰 그린다. 단계 구간은 시안의 10초 루프를 3초 한 번으로 줄인 것.
class BrainPainter extends CustomPainter {
  BrainPainter({required this.t, required this.nodes});

  final double t;
  final List<BrainNode> nodes;

  static const _view = Size(350, 300);

  /// [t]를 [a]~[b] 구간에서 0~1로 편다.
  double _phase(double a, double b, [Curve curve = Curves.easeOut]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _view.width,
      size.height / _view.height,
    );
    canvas
      ..save()
      ..translate(
        (size.width - _view.width * scale) / 2,
        (size.height - _view.height * scale) / 2,
      )
      ..scale(scale);

    // ① 윤곽 → ② 안쪽 채움 → ③ 소뇌·뇌간(살짝 내려오며) → ④ 주름
    final fill = _phase(0.15, 0.25);
    final base = _phase(0.22, 0.32);
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
      _phase(0, 0.17, Curves.easeInOut),
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
      _drawPartial(canvas, f, _phase(0.28, 0.42), foldPaint);
    }

    // ⑥ 연결선(원보다 먼저 그려 원 아래에 깔린다): 원이 다 떠오른 뒤 0.60~0.75
    final byTag = {for (final n in nodes) n.interest.tag: n};
    final linkPaint = Paint()
      ..color = AppBrain.outline
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final drawn = <String>{};
    final links = _phase(0.60, 0.75);
    for (final n in nodes) {
      for (final other in n.interest.linkedTags) {
        final m = byTag[other];
        final key = ([n.interest.tag, other]..sort()).join('\u0000');
        if (m == null || !drawn.add(key) || links == 0) continue;
        canvas.drawLine(
          n.center,
          Offset.lerp(n.center, m.center, links)!,
          linkPaint,
        );
      }
    }

    // ⑤ 관심사 원: 0.40~0.62, 많이 캡처한 것부터 차례로 통통 튀며
    // ⑦ 잊은 관심사: 처음엔 흐릿하게(28%) 떠 있다가 0.78~0.92에 레몬색으로 깨어나며 고리가 퍼진다
    final wake = _phase(0.78, 0.92);
    final halo = _phase(0.80, 1.0);
    for (final n in nodes) {
      final start = 0.40 + 0.03 * n.rank;
      final pop = _phase(start, start + 0.10, Curves.elasticOut);
      if (pop <= 0) continue;
      final forgotten = n.interest.forgotten;
      final alpha = forgotten ? 0.28 + 0.72 * wake : 1.0;
      final bump = forgotten ? 1 + 0.18 * math.sin(math.pi * wake) : 1.0;
      final r = n.radius * pop * bump;
      if (forgotten && halo > 0 && halo < 1) {
        canvas.drawCircle(
          n.center,
          n.radius * (1 + 1.4 * halo),
          Paint()
            ..color = AppColors.lemon.withValues(alpha: 0.7 * (1 - halo))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      final color = forgotten
          ? AppColors.lemon
          : n.rank == 0
          ? AppColors.celadon
          : AppColors.celadonSoft;
      canvas.drawCircle(
        n.center,
        r,
        Paint()..color = color.withValues(alpha: alpha),
      );
      _label(canvas, n, r, alpha);
    }
    canvas.restore();
  }

  void _drawPartial(Canvas canvas, Path path, double fraction, Paint paint) {
    if (fraction <= 0) return;
    for (final PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * fraction), paint);
    }
  }

  // 원 안 글자: "#태그"(1위는 아래에 횟수도). 원보다 길면 줄여서 말줄임.
  void _label(Canvas canvas, BrainNode n, double r, double alpha) {
    if (r < 8) return;
    final ink = AppColors.ink.withValues(alpha: alpha);
    final tag = TextPainter(
      text: TextSpan(
        text: '#${n.interest.tag}',
        style: AppText.caption.copyWith(
          fontSize: n.rank == 0 ? 13 : 10.5,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: r * 2 - 6);
    final count = n.rank == 0
        ? (TextPainter(
            text: TextSpan(
              text: '${n.interest.captureCount}',
              style: AppText.numBadge().copyWith(color: ink, fontSize: 13),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;
    final h = tag.height + (count?.height ?? 0);
    var y = n.center.dy - h / 2;
    tag.paint(canvas, Offset(n.center.dx - tag.width / 2, y));
    y += tag.height;
    count?.paint(canvas, Offset(n.center.dx - count.width / 2, y));
  }

  @override
  bool shouldRepaint(BrainPainter old) => old.t != t || old.nodes != nodes;
}
