import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/ocr_store.dart';
import '../data/device/trash_store.dart';
import '../data/remine_store.dart';
import '../data/tidy_bundles.dart';
import '../models/screenshot_item.dart';
import '../widgets/grow_column.dart';
import '../widgets/tidy_bento.dart';
import 'tidy_bundle_screen.dart';
import 'trash_screen.dart';

/// 정리 탭: 지워도 될 만한 캡처 묶음을 벤토 그리드로 보여 준다(디자인 캔버스 20안 O).
///
/// - 묶음은 기기 안에서만 계산한다([computeBundles]). 가짜 데이터 모드(크롬)는 보여 주기용 묶음([demoBundles]).
/// - 다시 계산하는 건 캡처 목록(저장소 revision)이나 휴지통이 바뀌었을 때뿐이다. 탭에 들어올 때는 휴지통 기록만 읽어
///   바뀌었는지 본다.
/// - 용량은 묶음에 든 캡처의 파일 크기만 읽고 asset id별로 기억한다(탭을 열 때마다 다시 읽지 않는다).
/// - 휴지통 타일·이번 주 막대는 기기 모드에서만(가짜 모드엔 휴지통 기록이 없다).
class TidyScreen extends StatefulWidget {
  const TidyScreen({super.key, this.active = true});

  /// 탭이 보이는 중인지. 처음 보일 때 계산하고, 다시 보일 때 바뀐 게 있으면 다시 센다.
  final bool active;

  @override
  State<TidyScreen> createState() => _TidyScreenState();
}

class _TidyScreenState extends State<TidyScreen> {
  TidyBundles? _bundles;
  int? _trashCount;

  /// 이번 주 휴지통 기록(기기 모드만). 화면은 build에서 [weekOf]로 만든다(용량을 나중에 읽어도 바로 반영).
  List<TrashLogEntry>? _log;

  /// 크기가 비어 있어 한 번 읽어 본 기록의 asset id. 못 읽었어도(영구 삭제) 다시 읽지 않는다.
  final Set<String> _sizeTried = {};

  /// 지금 남은 장수(휴지통·숨김 제외). 묶음을 계산할 때 같이 센다.
  int _remaining = 0;

  /// asset id → 파일 크기. 못 읽은 장은 0으로 기억해 다시 묻지 않는다.
  final Map<String, int> _sizes = {};

  /// 마지막으로 계산한 기준(revision, 휴지통 asset id들). 같으면 묶음을 다시 계산하지 않는다.
  (int, String)? _computedFor;
  int _revision = -1;
  int _loadToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RemineScope를 읽어 두면 캡처 목록이 바뀔 때(휴지통·카테고리 수정 등) 여기로 다시 온다.
    final revision = RemineScope.of(context).revision;
    if (revision != _revision) {
      _revision = revision;
      if (widget.active) _load();
    }
  }

  @override
  void didUpdateWidget(TidyScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final store = RemineScope.of(context);
    final device = DeviceScope.maybeOf(context);
    final trash = device?.trash;
    final now = store.now();

    final hidden = trash == null
        ? const <String>{}
        : {for (final t in await trash.store.hidden()) t.assetId};
    final trashCount = trash == null ? null : (await trash.store.all()).length;
    final log = trash == null
        ? null
        : await trash.store.trashedSince(weekStart(now));
    final key = (store.revision, (hidden.toList()..sort()).join(','));

    var bundles = _bundles;
    var remaining = _remaining;
    if (bundles == null || key != _computedFor) {
      final items = await store.repository.all();
      remaining = items.where((s) => !hidden.contains(s.localAssetId)).length;
      bundles = trash == null
          ? demoBundles(items, now)
          : computeBundles(
              items,
              now,
              skip: hidden,
              twins: await _twins(items, hidden, trash.ocr),
              twinsReady: true,
            );
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _bundles = bundles;
      _computedFor = key;
      _trashCount = trashCount;
      _remaining = remaining;
      _log = log;
    });

    final reader = device?.reader;
    if (reader == null || trash == null) return;

    // 크기 기록 전(크기 없는) 이번 주 기록: 파일이 아직 남아 있으면 읽어 채운다. 한 번 물어본 장은 다시 안 읽는다.
    final unsized = [
      for (final e in log ?? const <TrashLogEntry>[])
        if (e.size == null && _sizeTried.add(e.assetId)) e.assetId,
    ];
    if (unsized.isNotEmpty) {
      final found = await reader.fileSizes(unsized);
      if (found.isNotEmpty) {
        await trash.store.fillSizes(found);
        final filled = await trash.store.trashedSince(weekStart(now));
        if (!mounted || token != _loadToken) return;
        setState(() => _log = filled);
      }
    }

    // 용량: 묶음에 든 캡처 중 아직 안 읽은 것만.
    final missing = [
      for (final s in bundles.all)
        if (!_sizes.containsKey(s.localAssetId)) s.localAssetId,
    ];
    if (missing.isEmpty) return;
    final read = await reader.fileSizes(missing);
    if (!mounted) return;
    setState(() {
      for (final id in missing) {
        _sizes[id] = read[id] ?? 0;
      }
    });
  }

  /// 쌍둥이 묶음. 후보(같은 앱 60초 안)만 OCR 원문을 메인에서 읽고, 비교는 다른 isolate에서 한다(탭이 버벅이지 않게).
  static Future<List<List<ScreenshotItem>>> _twins(
    List<ScreenshotItem> items,
    Set<String> hidden,
    OcrStore ocr,
  ) async {
    final candidates = twinCandidates([
      for (final s in items)
        if (!hidden.contains(s.localAssetId)) s,
    ]);
    if (candidates.isEmpty) return const [];
    final inputs = <TwinInput>[];
    for (final s in candidates) {
      final text = (await ocr.find(s.localAssetId))?.text ?? '';
      if (text.isNotEmpty) {
        inputs.add(TwinInput(s.localAssetId, s.sourceApp!, s.takenAt, text));
      }
    }
    final groups = await compute(findTwins, inputs);
    final byAsset = {for (final s in candidates) s.localAssetId: s};
    return [
      for (final g in groups) [for (final id in g) byAsset[id]!],
    ];
  }

  String? get _sizeText {
    final bundles = _bundles;
    if (bundles == null || DeviceScope.maybeOf(context) == null) return null;
    var total = 0;
    for (final s in bundles.all) {
      final b = _sizes[s.localAssetId];
      if (b == null) return null; // 아직 읽는 중
      total += b;
    }
    return sizeLabel(total);
  }

  Future<void> _open(TidyKind? kind) async {
    final b = _bundles;
    if (b == null) return;
    final twins = TidySection(
      '비슷한 스크린샷',
      [for (final g in b.twins) ...g],
      keep: {for (final g in b.twins) g.first.id},
    );
    final stale = TidySection('3달째 안 봄', b.stale);
    final etc = TidySection('갈 곳 없는 스크린샷', b.etc);
    final (title, sections) = switch (kind) {
      null => ('비울 수 있는 스크린샷', [twins, stale, etc]),
      TidyKind.twins => (twins.title, [twins]),
      TidyKind.stale => (stale.title, [stale]),
      TidyKind.etc => (etc.title, [etc]),
    };
    await Navigator.of(context).push(
      fadeThroughRoute(
        context,
        (_) => TidyBundleScreen(title: title, sections: sections),
        heroes: false,
      ),
    );
  }

  Future<void> _openTrash() async {
    final trash = DeviceScope.maybeOf(context)?.trash;
    if (trash == null) return;
    await Navigator.of(context).push(
      fadeThroughRoute(
        context,
        (_) => TrashScreen(trash: trash),
        heroes: false,
      ),
    );
    if (mounted) _load(); // 휴지통에서 되살리거나 지웠을 수 있다
  }

  @override
  Widget build(BuildContext context) {
    final bundles = _bundles;
    final log = _log;
    // 크기를 하나도 모르는 주는 지금 목록 스크린샷의 평균 크기(이미 읽어 둔 캐시)로 추정한다.
    final known = [
      for (final b in _sizes.values)
        if (b > 0) b,
    ];
    final week = log == null
        ? null
        : weekOf(
            log,
            RemineScope.of(context).now(),
            _remaining,
            listAverage: known.isEmpty
                ? null
                : known.reduce((a, b) => a + b) / known.length,
          );
    // 화면이 남으면 남는 높이의 [AppTidy.topGrowShare](최대 [AppTidy.topGrowMax])를 제목 위에 더해
    // 제목~이번 주 막대 전체를 아래로 내린다. 내용이 더 길면 위 여백 없이 평소처럼 스크롤한다(홈과 같은 GrowColumn).
    const top = AppSpacing.s16;
    const bottom = AppSpacing.s24;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            top,
            AppSpacing.screenPadding,
            bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, viewport.maxHeight - top - bottom),
            ),
            child: GrowColumn(
              children: [
                const GrowGap(
                  0,
                  key: ValueKey('tidy-top-gap'),
                  share: AppTidy.topGrowShare,
                  maxExtra: AppTidy.topGrowMax,
                ),
                Text('정리', style: AppText.title),
                const SizedBox(height: AppSpacing.s8),
                Text('지워도 될 만한 스크린샷을 모아 드릴게요', style: AppText.caption),
                const SizedBox(height: AppSpacing.s24),
                if (bundles != null) ...[
                  TidyBento(
                    bundles: bundles,
                    size: _sizeText,
                    trashCount: _trashCount,
                    onOpen: _open,
                    onTrash: _openTrash,
                  ),
                  if (week != null) ...[
                    const SizedBox(height: AppTidy.weekTopGap),
                    TidyWeekStamps(week: week),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
