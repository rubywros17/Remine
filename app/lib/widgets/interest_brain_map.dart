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
  bool _logged = false;

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
                        if (kDebugMode && !_logged && chips.isNotEmpty) {
                          _logged = true;
                          debugPrint(
                            brainLinkSummary(
                              [for (final c in chips) c.node],
                              rects: {
                                for (final c in chips) c.node.rank: c.rect,
                              },
                            ),
                          );
                        }
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

/// 지도 위 관심사 하나와 그 자리.
class BrainNode {
  const BrainNode(this.interest, this.seat, this.rank);

  final Interest interest;

  /// -1은 가운데(1등), 0~5는 둘레 육각형 자리([hexSeat] 각도 순서, 원형으로 이웃).
  final int seat;

  /// 0이 가장 많이 캡처한 것(가장 먼저·가장 크게 떠오른다).
  final int rank;

  /// 반지름 1인 육각형 위 자리(모양만, 가운데 = 원점). 칩 위치가 없을 때 거리 비교에 쓴다.
  Offset get slot => seat < 0 ? Offset.zero : hexSeat(seat, 1);
}

/// 둘레 자리 수. 0 오른 → 1 오른아래 → 2 왼아래 → 3 왼 → 4 왼위 → 5 오른위(60도 간격, 5 다음은 0).
const _seats = 6;

/// 둘레 [seat]의 위치(가운데 기준): 가로 반지름 [rx], 세로는 [AppBrain.hexAspect]배로 납작한 타원 위 60도 간격.
Offset hexSeat(int seat, double rx) {
  final a = seat * math.pi / 3;
  return Offset(math.cos(a) * rx, math.sin(a) * rx * AppBrain.hexAspect);
}

/// 자리별 좁은 정도(글자 1개당 비용). 좌우 끝이 가장 좁고, 위 줄은 뇌 앞쪽(왼위)이 둥글게 깎여 오른위보다 좁다.
/// 아래 줄이 가장 넓다. 긴 키워드는 숫자가 작은 자리로.
const _seatTightness = [10, 0, 0, 10, 4, 2];

/// 잊은 관심사 몫. 나머지([AppBrain.maxNodes] - 이것)는 요즘 모으는 중.
const _forgottenShare = 4;

/// 지도에 올릴 관심사를 순위 순서로 고른다. [interests]는 서버 순서(그룹 안에서 장수 많은 순).
/// 잊은 것 4 + 요즘 것 3, 한쪽이 모자라면 다른 쪽에서 채워 최대 [AppBrain.maxNodes]개.
/// 1등은 잊은 것 1등(없으면 요즘 1등), 그 뒤는 상대 그룹부터 번갈아.
List<Interest> pickBrainInterests(List<Interest> interests) {
  final max = math.min(AppBrain.maxNodes, _seats + 1);
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

/// [pickBrainInterests]로 고른 관심사를 자리에 앉힌다. 1등은 가운데, 나머지는 [_assignSeats].
List<BrainNode> layoutNodes(List<Interest> interests) {
  final picked = pickBrainInterests(interests);
  final seats = _assignSeats(picked.skip(1).toList());
  return [
    for (final (rank, interest) in picked.indexed)
      BrainNode(interest, rank == 0 ? -1 : seats[rank - 1], rank),
  ];
}

/// 1등 뒤 칩들의 둘레 자리. 자리 좌표는 고정이고 누가 어디 앉는지만 정한다.
/// 모든 경우(최대 6! = 720)를 따져 비용이 가장 작은 것(같으면 먼저 본 것 → 결정적). 비용은 앞 것일수록 크다:
/// ① 같은 카테고리 묶음이 끊긴 수(이웃 자리끼리 이어지게) ② 좁은 자리에 앉은 글자 수(긴 키워드는 위·아래로, [_seatTightness])와
/// 위·아래 줄 글자 수 합 중 큰 쪽 ③ 이웃 자리끼리 잊은/요즘이 같은 수(번갈아는 가능한 만큼만).
// ponytail: 칩 7개라 전부 따져 본다. 자리가 늘면 탐욕 배치로 바꾼다.
List<int> _assignSeats(List<Interest> rest) {
  if (rest.isEmpty) return const [];
  var best = <int>[];
  var bestCost = double.infinity;
  for (final perm in _permutations([for (var i = 0; i < _seats; i++) i])) {
    final idx = perm.take(rest.length).toList();
    final at = <int, Interest>{for (final (i, it) in rest.indexed) idx[i]: it};
    var cost = 0.0;
    // ① 카테고리마다 이어진 덩어리 수 = 칩 수 - 이웃끼리 같은 쌍(한 바퀴 다 차면 1). 덩어리가 1보다 많으면 끊긴 것.
    final count = <Category, int>{};
    final joined = <Category, int>{};
    for (final it in rest) {
      count[it.category] = (count[it.category] ?? 0) + 1;
    }
    for (var k = 0; k < _seats; k++) {
      final a = at[k];
      final b = at[(k + 1) % _seats];
      if (a == null || b == null) continue;
      if (a.category == b.category) {
        joined[a.category] = (joined[a.category] ?? 0) + 1;
      }
      if (a.forgotten == b.forgotten) cost += 1; // ③
    }
    for (final MapEntry(key: c, value: m) in count.entries) {
      final pieces = math.max(1, m - (joined[c] ?? 0));
      cost += 1000 * (pieces - 1); // ①
    }
    for (final MapEntry(key: seat, value: it) in at.entries) {
      cost += _seatTightness[seat] * it.tag.length; // ②
    }
    // ② 위(4·5)·아래(1·2) 줄은 두 칩이 나란히 앉아 그 글자 수 합이 반지름을 정한다 → 더 긴 줄을 짧게(긴 칩끼리 한 줄 피하기).
    int row(int a, int b) =>
        (at[a]?.tag.length ?? 0) + (at[b]?.tag.length ?? 0);
    cost += 5 * math.max(row(4, 5), row(1, 2));
    if (cost < bestCost - 1e-9) {
      bestCost = cost;
      best = idx;
    }
  }
  return best;
}

/// 칩 순열(사전순). [Dart 메모] sync*는 값을 하나씩 내주는 제너레이터(자바 Iterator를 직접 짜는 것과 같다).
Iterable<List<int>> _permutations(List<int> items) sync* {
  if (items.length <= 1) {
    yield items;
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final rest = [...items]..removeAt(i);
    for (final p in _permutations(rest)) {
      yield [items[i], ...p];
    }
  }
}

/// Prim 최소 신장 트리: 이미 이은 것들에서 가장 가까운 것을 하나씩 붙인다. 붙인 순서대로 (트리 쪽, 새 것).
// ponytail: 칩 7개라 O(n³) 단순 탐색으로 충분.
List<(T, T)> _prim<T>(List<T> items, double Function(T, T) cost) {
  if (items.isEmpty) return const [];
  final inTree = [items.first];
  final left = items.skip(1).toList();
  final edges = <(T, T)>[];
  while (left.isNotEmpty) {
    var best = (from: inTree.first, to: left.first, d: double.infinity);
    for (final a in inTree) {
      for (final b in left) {
        final d = cost(a, b);
        if (d < best.d) best = (from: a, to: b, d: d);
      }
    }
    edges.add((best.from, best.to));
    inTree.add(best.to);
    left.remove(best.to);
  }
  return edges;
}

/// 선 종류: 같은 카테고리(실선) · 같은 캡처(점선) · 외톨이 칩을 가장 가까운 칩에 잇는 연한 선.
enum BrainLinkKind { solid, dashed, faint }

/// 연결선 하나: 순위 [a] < [b].
typedef BrainLink = ({int a, int b, BrainLinkKind kind});

/// 선이 지나가는(양 끝이 아닌) 칩들. 칩 뒤로 선이 지나가면 그 칩에서 나온 선처럼 보인다.
List<int> brainLinkCrossings(BrainLink l, Map<int, Rect> rects) {
  final a = rects[l.a]!.center;
  final b = rects[l.b]!.center;
  return [
    for (final MapEntry(key: rank, value: r) in rects.entries)
      if (rank != l.a && rank != l.b && _segmentHits(a, b, r.deflate(2))) rank,
  ];
}

// ponytail: 선분 위 점 24개로 검사. 칩이 아주 얇아지면 정확한 선분-사각형 교차로 바꾼다.
bool _segmentHits(Offset a, Offset b, Rect r) {
  for (var i = 1; i < 24; i++) {
    if (r.contains(Offset.lerp(a, b, i / 24)!)) return true;
  }
  return false;
}

/// 연결선 목록. 그리는 순서도 이 순서다(실선 → 점선 → 연한 선).
/// - 실선: 같은 카테고리끼리. 다 잇지 않고 가까운 칩끼리 짧은 선부터 한 줄로(최소 신장 트리, n개면 n-1개).
/// - 점선: [Interest.linkedTags]. 같은 카테고리 쌍은 이미 실선으로 이어져 있어 긋지 않는다.
/// - 연한 선: 실선·점선이 하나도 없는 칩을 가장 가까운 칩에 하나. 개수는 자리와 상관없다(애니메이션 길이가 고정).
/// [rects](순위 → 칩 사각형, 캔버스)가 있으면 그 위치로 재고, 다른 칩 뒤를 지나가는 선은 되도록 피한다.
/// 없으면 [BrainNode.slot]으로 잰다(개수는 같다).
List<BrainLink> brainLinks(List<BrainNode> nodes, {Map<int, Rect>? rects}) {
  Offset at(BrainNode n) => rects?[n.rank]?.center ?? n.slot;
  double cost(BrainNode a, BrainNode b) {
    final d = (at(a) - at(b)).distance;
    if (rects == null) return d;
    final crossed = brainLinkCrossings((
      a: a.rank,
      b: b.rank,
      kind: BrainLinkKind.solid,
    ), rects).isNotEmpty;
    return crossed ? d + 1e6 : d;
  }

  BrainLink link(BrainNode x, BrainNode y, BrainLinkKind kind) =>
      (a: math.min(x.rank, y.rank), b: math.max(x.rank, y.rank), kind: kind);

  // [Dart 메모] 맵은 넣은 순서를 지켜서 카테고리는 첫 등장 순위 순.
  final byCategory = <Category, List<BrainNode>>{};
  for (final n in nodes) {
    (byCategory[n.interest.category] ??= []).add(n);
  }
  final links = <BrainLink>[
    for (final group in byCategory.values)
      for (final (x, y) in _prim(group, cost)) link(x, y, BrainLinkKind.solid),
  ];
  final byTag = {for (final n in nodes) n.interest.tag: n};
  final dashed = <BrainLink>{};
  for (final n in nodes) {
    for (final tag in n.interest.linkedTags) {
      final m = byTag[tag];
      if (m == null || m == n || m.interest.category == n.interest.category) {
        continue;
      }
      dashed.add(link(n, m, BrainLinkKind.dashed));
    }
  }
  links.addAll(dashed);
  // 외톨이: 이어진 칩과 앞 순위 외톨이 중 가장 가까운 칩에(이어진 칩이 하나도 없으면 첫 외톨이만 선 없음).
  final joined = {
    for (final l in links) ...[l.a, l.b],
  };
  final targets = [
    for (final n in nodes)
      if (joined.contains(n.rank)) n,
  ];
  for (final n in nodes.where((n) => !joined.contains(n.rank))) {
    if (targets.isNotEmpty) {
      final near = targets.reduce((p, q) => cost(n, q) < cost(n, p) ? q : p);
      links.add(link(n, near, BrainLinkKind.faint));
    }
    targets.add(n);
  }
  return links;
}

/// 선 하나의 붓. 실선은 그 카테고리 색(홈 서랍 점과 같은 토큰)을 보정한 색, 점선·연한 선은 흰색.
Paint brainLinkPaint(BrainLink link, Category category) => switch (link.kind) {
  BrainLinkKind.solid =>
    Paint()
      ..color = AppBrain.linkColor(category)
      ..strokeWidth = AppBrain.linkStroke
      ..strokeCap = StrokeCap.round,
  BrainLinkKind.dashed =>
    Paint()
      ..color = AppBrain.linkDashColor
      ..strokeWidth = AppBrain.linkDashStroke,
  BrainLinkKind.faint =>
    Paint()
      ..color = AppBrain.linkFaintColor
      ..strokeWidth = AppBrain.linkFaintStroke
      ..strokeCap = StrokeCap.round,
};

/// 디버그 로그. 첫 줄은 요약
/// "[brain] 실선 N(카테고리별 개수) · 점선 M · 같은 캡처 쌍 K(같은 카테고리라 생략 L) · 연한 선 F",
/// 그 뒤로 선마다 (a, b, 종류, 색, 두 칩 카테고리)와 뒤로 지나가는 칩.
String brainLinkSummary(List<BrainNode> nodes, {Map<int, Rect>? rects}) {
  final links = brainLinks(nodes, rects: rects);
  final byRank = {for (final n in nodes) n.rank: n};
  int count(BrainLinkKind k) => links.where((l) => l.kind == k).length;
  final perCategory = <String, int>{};
  for (final l in links.where((l) => l.kind == BrainLinkKind.solid)) {
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
  final detail = [for (final e in perCategory.entries) '${e.key} ${e.value}'];
  String tag(int rank) => byRank[rank]!.interest.tag;
  return [
    '[brain] 실선 ${count(BrainLinkKind.solid)}(${detail.join(', ')}) · '
        '점선 ${count(BrainLinkKind.dashed)} · '
        '같은 캡처 쌍 ${pairs.length}(같은 카테고리라 생략 $sameCategory) · '
        '연한 선 ${count(BrainLinkKind.faint)}',
    for (final l in links)
      () {
        final ca = byRank[l.a]!.interest.category;
        final cb = byRank[l.b]!.interest.category;
        final color = brainLinkPaint(l, ca).color.toARGB32();
        final crossed = rects == null
            ? const <int>[]
            : brainLinkCrossings(l, rects);
        return '[brain]   (${tag(l.a)}, ${tag(l.b)}, ${l.kind.name}, '
            '#${color.toRadixString(16).padLeft(8, '0')}, ${ca.label}/${cb.label})'
            '${crossed.isEmpty ? '' : ' 뒤로 지나감: ${crossed.map(tag).join(', ')}'}';
      }(),
  ].join('\n');
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
  Offset toBrain(Offset p) => focus + (p - size.center(Offset.zero)) / scale;
  Rect rectToCanvas(Rect r) =>
      Rect.fromPoints(toCanvas(r.topLeft), toCanvas(r.bottomRight));

  void apply(Canvas canvas) => canvas
    ..translate(size.width / 2, size.height / 2)
    ..scale(scale)
    ..translate(-focus.dx, -focus.dy);
}

/// 키워드 칩 하나(캔버스 좌표). [shrink]는 이 칩의 글자 크기 배율(긴 칩만 따로 더 줄 수 있다).
/// 가로 패딩도 같은 배율로 줄고, 높이는 같은 줄 칩들과 같게 둔다(글자만 작아지고 칩 줄은 맞는다).
class BrainChip {
  const BrainChip(this.node, this.rect, [this.shrink = 1]);

  final BrainNode node;
  final Rect rect;
  final double shrink;

  bool get top => node.rank == 0;
  Color get color =>
      top || node.interest.forgotten ? AppBrain.chipTop : AppBrain.chip;
  EdgeInsets get padding => _chipPadding(node, shrink);
}

/// 칩 패딩: 세로는 그대로, 가로는 글자 배율만큼 줄인다.
EdgeInsets _chipPadding(BrainNode n, double shrink) {
  final base = n.rank == 0 ? AppBrain.chipTopPadding : AppBrain.chipPadding;
  return EdgeInsets.symmetric(
    vertical: base.top,
    horizontal: base.left * shrink,
  );
}

TextPainter _chipText(
  BrainNode n,
  double maxWidth,
  TextScaler scaler, [
  double shrink = 1,
]) => TextPainter(
  text: TextSpan(
    text: n.interest.tag,
    style: AppText.label.copyWith(
      fontSize:
          (n.rank == 0 ? AppBrain.chipTopFont : AppBrain.chipFont) * shrink,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
      height: 1.2,
    ),
  ),
  textAlign: TextAlign.center,
  textDirection: TextDirection.ltr,
  textScaler: scaler,
)..layout(maxWidth: maxWidth);

/// 칩이 뇌 윤곽 안에 [margin](캔버스 px)만큼 떨어져 들어가는지(모서리·변 가운데 8점이 대뇌 안).
bool chipFitsBrain(
  Size size,
  Rect chip, [
  double margin = AppBrain.chipBrainMinMargin,
]) {
  final frame = BrainFrame.end(size);
  final r = chip.inflate(margin);
  return [
    r.topLeft,
    r.topCenter,
    r.topRight,
    r.centerRight,
    r.bottomRight,
    r.bottomCenter,
    r.bottomLeft,
    r.centerLeft,
  ].every((p) => _cerebrum.contains(frame.toBrain(p)));
}

/// 육각형 가운데(캔버스): 대뇌 상자 안 [AppBrain.hexCenter] 비율 자리.
Offset brainHexCenter(Size size) {
  final b = _cerebrum.getBounds();
  return BrainFrame.end(size).toCanvas(
    b.topLeft +
        Offset(
          b.width * AppBrain.hexCenter.dx,
          b.height * AppBrain.hexCenter.dy,
        ),
  );
}

/// 칩들의 윤곽 여백(캔버스 px, 1px 단위): 모든 칩이 들어가는 가장 큰 값. 최대 [AppBrain.chipBrainMargin],
/// 윤곽 밖으로 나가면 음수(최소 -[_maxOut]). 여백은 클수록 다 들어가기 어려워서 이분 탐색한다.
double _brainRoom(Size size, List<Rect> rects) {
  bool fits(int m) => rects.every((r) => chipFitsBrain(size, r, m.toDouble()));
  var lo = -_maxOut; // 들어간다고 보는 값(아래)
  var hi = AppBrain.chipBrainMargin.toInt();
  if (fits(hi)) return hi.toDouble();
  if (!fits(lo)) return lo.toDouble();
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo.toDouble();
}

// 칩 높이(최소 약 25px)의 절반보다 작게: 더 줄이면 사각형이 뒤집혀 판정이 틀어진다.
const _maxOut = 10;

/// 칩 자리: 가운데 + 둘레 타원 육각형(고정 모양, 칩을 밀어내지 않는다). 칩 사이는 [AppBrain.chipSpacing] 이상,
/// 뇌 윤곽 여백은 [AppBrain.chipBrainMinMargin] 이상(그 안에서 가장 큰 반지름 쪽, 최대 [AppBrain.chipBrainMargin]).
/// 말줄임 없이 글자 크기로만 맞춘다. 맞추는 순서:
/// ① 육각형 반지름([AppBrain.hexRadius] 범위)을 키워 본다.
/// ② 넘치면 가장 넓은 칩부터 그 칩만 글자를 줄인다([AppBrain.chipEachShrinkStep]씩, 둘레 칩 최소
///    [AppBrain.chipEachMinShrink]·1등 최소 [AppBrain.chipTopEachMinShrink], 글자 [AppBrain.chipMinFont] 아래로는 안 내려감).
/// ③ 그래도 안 되면 전체 글자 배율([AppBrain.chipShrinks])을 낮추고 ②를 다시.
/// ④ 그래도 안 되면 가장 줄인 상태에서 윤곽에 가장 덜 걸리는 배치(캔버스 안), 그것도 안 되면 뒤 순위 칩부터
///    지도에서 뺀다(목록에는 그대로 있다). 순위 순서로 돌려준다.
List<BrainChip> layoutChips(
  List<BrainNode> nodes,
  Size size,
  TextScaler scaler,
) {
  if (nodes.isEmpty || size.isEmpty) return const [];
  final frame = BrainFrame.end(size);
  final center = brainHexCenter(size);
  final span = _cerebrum.getBounds().width * frame.scale;
  final canvas = (Offset.zero & size).inflate(_eps);

  // 글자 크기 재기(같은 칩·배율은 한 번만). 높이는 전체 배율 [g] 기준이라 같은 줄 칩들이 같다.
  final textSize = <(int, double), Size>{};
  Size measure(BrainNode n, double shrink) =>
      textSize[(n.rank, shrink)] ??= () {
        final pad = _chipPadding(n, shrink);
        final text = _chipText(n, size.width - pad.horizontal, scaler, shrink);
        final s = Size(text.width, text.height);
        text.dispose();
        return s;
      }();
  Size chipSize(BrainNode n, double shrink, double g) => Size(
    measure(n, shrink).width + _chipPadding(n, shrink).horizontal,
    measure(n, g).height + _chipPadding(n, g).vertical,
  );

  List<Rect> place(List<BrainNode> kept, List<double> f, double g, double k) =>
      [
        for (final (i, node) in kept.indexed)
          Rect.fromCenter(
            center:
                center +
                (node.seat < 0 ? Offset.zero : hexSeat(node.seat, k * span)),
            width: chipSize(node, f[i], g).width,
            height: chipSize(node, f[i], g).height,
          ),
      ];

  // 반지름을 키워 보며 칩 사이·캔버스를 지키는 배치들. [enough] 여백을 지키는 것 중 여백이 가장 큰 것.
  // 없으면 null, [loose]면 여백을 못 지켜도 윤곽에 가장 덜 걸리는 것.
  List<Rect>? fit(
    List<BrainNode> kept,
    List<double> f,
    double g, {
    bool loose = false,
  }) {
    List<Rect>? best;
    var bestRoom = double.negativeInfinity;
    for (
      var k = AppBrain.hexRadius.$1;
      k <= AppBrain.hexRadius.$2 + _eps;
      k += 0.01
    ) {
      final rects = place(kept, f, g, k);
      final inCanvas = rects.every(
        (r) => canvas.contains(r.topLeft) && canvas.contains(r.bottomRight),
      );
      if (!inCanvas || !_spaced(rects)) continue;
      // 빠른 거르기: 최소 여백도 안 되면 건너뛴다([loose]일 때만 끝까지 잰다).
      if (!loose && !rects.every((r) => chipFitsBrain(size, r))) continue;
      final room = _brainRoom(size, rects);
      if (room > bestRoom) {
        best = rects;
        bestRoom = room;
      }
    }
    return best;
  }

  for (var n = nodes.length; n > 0; n--) {
    // 칩을 뺐으면 남은 칩으로 자리를 다시 배정한다(빈자리가 생기면 긴 칩이 한 줄에 혼자 앉을 수 있다).
    final seats = n == nodes.length
        ? [for (final x in nodes.skip(1)) x.seat]
        : _assignSeats([for (final x in nodes.skip(1).take(n - 1)) x.interest]);
    final kept = [
      for (final (i, x) in nodes.take(n).indexed)
        BrainNode(x.interest, i == 0 ? -1 : seats[i - 1], x.rank),
    ];
    // 칩마다 더 줄일 수 있는 하한(기본 글자 대비 배율).
    final floor = [
      for (final x in kept)
        math.max(
          x.rank == 0
              ? AppBrain.chipTopEachMinShrink
              : AppBrain.chipEachMinShrink,
          AppBrain.chipMinFont /
              (x.rank == 0 ? AppBrain.chipTopFont : AppBrain.chipFont),
        ),
    ];
    var f = <double>[];
    var g = 1.0;
    for (g in AppBrain.chipShrinks) {
      f = [for (final x in floor) math.max(g, x)];
      while (true) {
        final rects = fit(kept, f, g);
        if (rects != null) {
          return [
            for (final (i, r) in rects.indexed) BrainChip(kept[i], r, f[i]),
          ];
        }
        // 가장 넓은 칩(아직 줄일 수 있는 것)만 한 단계 줄인다.
        int? widest;
        for (var i = 0; i < kept.length; i++) {
          if (f[i] <= floor[i] + _eps) continue;
          if (widest == null ||
              chipSize(kept[i], f[i], g).width >
                  chipSize(kept[widest], f[widest], g).width) {
            widest = i;
          }
        }
        if (widest == null) break;
        f[widest] = math.max(
          floor[widest],
          f[widest] - AppBrain.chipEachShrinkStep,
        );
      }
    }
    // 끝까지 최소 여백을 못 지키면 가장 줄인 상태에서 윤곽에 가장 덜 걸리는 배치(캔버스 안).
    final rects = fit(kept, f, g, loose: true);
    if (rects != null) {
      return [for (final (i, r) in rects.indexed) BrainChip(kept[i], r, f[i])];
    }
  }
  return const [];
}

/// 칩 테두리끼리 [AppBrain.chipSpacing] 이상 떨어져 있는지.
bool _spaced(List<Rect> rects) {
  const half = AppBrain.chipSpacing / 2 - _eps;
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (rects[i].inflate(half).overlaps(rects[j].inflate(half))) return false;
    }
  }
  return true;
}

const _eps = 0.01;

/// [ms](지도 시작 기준)에 맞춰 그린다. [intro]가 false면 얼굴·확대·빛 없이 마지막 크기에서 뇌부터.
class BrainPainter extends CustomPainter {
  BrainPainter({
    required this.ms,
    required this.intro,
    required this.chips,
    required this.textScaler,
  }) : links = brainLinks(
         [for (final c in chips) c.node],
         rects: {for (final c in chips) c.node.rank: c.rect},
       );

  final double ms;
  final bool intro;
  final List<BrainChip> chips;

  /// 칩 실제 위치로 정한 선(다른 칩 뒤를 지나가는 선은 되도록 피한다).
  final List<BrainLink> links;
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

  // 연결선은 칩 뒤에: 칩 가운데끼리, 하나씩 그려진다(점선도 앞에서부터 차례로, 연한 선은 맨 뒤).
  void _drawLinks(Canvas canvas) {
    final byRank = {for (final c in chips) c.node.rank: c};
    for (final (i, l) in links.indexed) {
      final start = AppBrain.linksStart + AppBrain.linkGap * i;
      final p = _phase((start, start + AppBrain.linkDraw), Curves.easeInOut);
      if (p <= 0) continue;
      final from = byRank[l.a]!.rect.center;
      final to = byRank[l.b]!.rect.center;
      final paint = brainLinkPaint(l, byRank[l.a]!.node.interest.category);
      if (l.kind != BrainLinkKind.dashed) {
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
        c.shrink,
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
