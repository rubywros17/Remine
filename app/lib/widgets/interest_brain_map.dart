import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/category.dart';
import '../models/interest.dart';
import 'app_button.dart';

/// 관심사 탭에 들어올 때마다 먼저 보여 주는 "머릿속 캡처 지도". 디자인 캔버스 19안 A.
///
/// 첫 진입: 왼쪽을 보는 옆얼굴 선 → 머릿속으로 확대(안쪽에 셀라돈 빛) → 뇌 윤곽 → 채움 → 소뇌·뇌간 → 주름
/// → 키워드 칩(1위부터) → 연결선(같은 카테고리 실선 · 같은 캡처 점선) → 제목. 시간표는 [AppBrain].
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

  /// 서버 순서. 잊은 것 4 · 요즘 것 3을 골라 지도에 올린다([pickBrainInterests]).
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
    if (kDebugMode) debugPrint(brainLinkSummary(_nodes));
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

// 시안의 자리(대뇌 안쪽). 0번은 가운데(1등).
// 1등 뒤로는 잊은 것·요즘 것이 번갈아 앉으므로, 홀수 자리(오른위·왼아래·오른끝아래)와
// 짝수 자리(오른아래·왼위·오른끝)가 각각 좌우·위아래로 퍼지게 순서를 정했다.
// (이 조건을 만족하는 순서 중 긴 키워드 7개가 360×800 뇌 안에 들어가는 것. 앞 3자리는 시안 그대로.)
const _slots = [
  Offset(150, 122),
  Offset(218, 92),
  Offset(206, 160),
  Offset(98, 168),
  Offset(92, 104),
  Offset(262, 176),
  Offset(268, 126),
];

/// 잊은 관심사 몫. 나머지([AppBrain.maxNodes] - 이것)는 요즘 모으는 중.
const _forgottenShare = 4;

/// 지도에 올릴 관심사를 순위 순서로 고른다. [interests]는 서버 순서(그룹 안에서 장수 많은 순).
/// 잊은 것 4 + 요즘 것 3, 한쪽이 모자라면 다른 쪽에서 채워 최대 [AppBrain.maxNodes]개.
/// 1등은 잊은 것 1등(없으면 요즘 1등), 그 뒤는 상대 그룹부터 번갈아.
List<Interest> pickBrainInterests(List<Interest> interests) {
  final max = math.min(AppBrain.maxNodes, _slots.length);
  final f = interests.where((i) => i.forgotten).toList();
  final r = interests.where((i) => !i.forgotten).toList();
  final nf = math.min(f.length, math.max(_forgottenShare, max - r.length));
  final nr = math.min(r.length, max - nf);
  final (first, second) = nf > 0
      ? (f.take(nf).toList(), r.take(nr).toList())
      : (r.take(nr).toList(), <Interest>[]);
  if (first.isEmpty) return const [];
  final rest = first.skip(1).toList();
  return [
    first.first,
    for (var i = 0; i < math.max(rest.length, second.length); i++) ...[
      if (i < second.length) second[i],
      if (i < rest.length) rest[i],
    ],
  ];
}

/// [pickBrainInterests]로 고른 관심사를 순위대로 자리에 앉힌다.
List<BrainNode> layoutNodes(List<Interest> interests) => [
  for (final (rank, interest) in pickBrainInterests(interests).indexed)
    BrainNode(interest, _slots[rank], rank),
];

/// 연결선 하나: 순위 [a] < [b]. [dashed]면 같은 캡처에 함께 붙은 관심사(점선), 아니면 같은 카테고리(실선).
typedef BrainLink = ({int a, int b, bool dashed});

/// 연결선 목록. 그리는 순서도 이 순서다(실선 먼저, 그다음 점선).
/// - 실선: 같은 카테고리끼리. 다 잇지 않고 가까운 자리끼리 짧은 선부터 한 줄로(최소 신장 트리, n개면 n-1개).
/// - 점선: [Interest.linkedTags]. 같은 카테고리 쌍은 이미 실선으로 이어져 있어 긋지 않는다.
List<BrainLink> brainLinks(List<BrainNode> nodes) {
  final links = <BrainLink>[];
  // [Dart 메모] groupBy 대신 맵에 차례로 넣는다. 맵은 넣은 순서를 지켜서 카테고리는 첫 등장 순위 순.
  final byCategory = <Category, List<BrainNode>>{};
  for (final n in nodes) {
    (byCategory[n.interest.category] ??= []).add(n);
  }
  for (final group in byCategory.values) {
    // Prim: 이미 이은 칩들에서 가장 가까운 칩을 하나씩 붙인다.
    // ponytail: 칩 7개라 O(n³) 단순 탐색으로 충분.
    final inTree = [group.first];
    final left = group.skip(1).toList();
    while (left.isNotEmpty) {
      var best = (from: inTree.first, to: left.first, d: double.infinity);
      for (final a in inTree) {
        for (final b in left) {
          final d = (a.slot - b.slot).distance;
          if (d < best.d) best = (from: a, to: b, d: d);
        }
      }
      links.add((
        a: math.min(best.from.rank, best.to.rank),
        b: math.max(best.from.rank, best.to.rank),
        dashed: false,
      ));
      inTree.add(best.to);
      left.remove(best.to);
    }
  }
  final byTag = {for (final n in nodes) n.interest.tag: n};
  final dashed = <(int, int)>{};
  for (final n in nodes) {
    for (final tag in n.interest.linkedTags) {
      final m = byTag[tag];
      if (m == null || m == n || m.interest.category == n.interest.category) {
        continue;
      }
      dashed.add((math.min(n.rank, m.rank), math.max(n.rank, m.rank)));
    }
  }
  return [...links, for (final (a, b) in dashed) (a: a, b: b, dashed: true)];
}

/// 선 하나의 붓: 실선은 그 카테고리 색(홈 서랍 점과 같은 색), 점선은 흰색.
Paint brainLinkPaint(BrainLink link, Category category) => link.dashed
    ? (Paint()
        ..color = AppBrain.linkDashColor
        ..strokeWidth = AppBrain.linkDashStroke)
    : (Paint()
        ..color = AppBrain.linkColor(category)
        ..strokeWidth = AppBrain.linkStroke
        ..strokeCap = StrokeCap.round);

/// 디버그 로그 한 줄: "[brain] 실선 N(카테고리별 개수) · 점선 M · 같은 캡처 쌍 K(같은 카테고리라 생략 L)".
String brainLinkSummary(List<BrainNode> nodes) {
  final links = brainLinks(nodes);
  final byRank = {for (final n in nodes) n.rank: n};
  final perCategory = <String, int>{};
  for (final l in links.where((l) => !l.dashed)) {
    final label = byRank[l.a]!.interest.category.label;
    perCategory[label] = (perCategory[label] ?? 0) + 1;
  }
  final byTag = {for (final n in nodes) n.interest.tag: n};
  final pairs = <(int, int)>{};
  var sameCategory = 0;
  for (final n in nodes) {
    for (final tag in n.interest.linkedTags) {
      final m = byTag[tag];
      if (m == null || m == n) continue;
      final added = pairs.add((
        math.min(n.rank, m.rank),
        math.max(n.rank, m.rank),
      ));
      if (added && m.interest.category == n.interest.category) sameCategory++;
    }
  }
  final solid = links.where((l) => !l.dashed).length;
  final detail = [for (final e in perCategory.entries) '${e.key} ${e.value}'];
  return '[brain] 실선 $solid(${detail.join(', ')}) · '
      '점선 ${links.length - solid} · '
      '같은 캡처 쌍 ${pairs.length}(같은 카테고리라 생략 $sameCategory)';
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

  // 연결선은 칩 뒤에: 칩 가운데끼리, 하나씩 그려진다(점선도 앞에서부터 차례로).
  void _drawLinks(Canvas canvas) {
    final byRank = {for (final c in chips) c.node.rank: c};
    for (final (i, l) in brainLinks([for (final c in chips) c.node]).indexed) {
      final start = AppBrain.linksStart + AppBrain.linkGap * i;
      final p = _phase((start, start + AppBrain.linkDraw), Curves.easeInOut);
      if (p <= 0) continue;
      final from = byRank[l.a]!.rect.center;
      final to = byRank[l.b]!.rect.center;
      final paint = brainLinkPaint(l, byRank[l.a]!.node.interest.category);
      if (!l.dashed) {
        canvas.drawLine(from, Offset.lerp(from, to, p)!, paint);
        continue;
      }
      final len = (to - from).distance;
      if (len == 0) continue;
      final dir = (to - from) / len;
      final end = len * p;
      for (
        var d = 0.0;
        d < end;
        d += AppBrain.linkDash + AppBrain.linkDashGap
      ) {
        canvas.drawLine(
          from + dir * d,
          from + dir * math.min(d + AppBrain.linkDash, end),
          paint,
        );
      }
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
