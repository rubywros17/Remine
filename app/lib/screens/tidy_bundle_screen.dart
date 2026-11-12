import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/screenshot_item.dart';
import '../widgets/app_button.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/peek_preview.dart';
import '../widgets/selectable_thumb.dart';
import '../widgets/small_widgets.dart';

/// 묶음 그리드의 한 묶음. [keep]의 캡처는 처음에 선택하지 않는다(쌍둥이의 가장 최근 1장 등).
class TidySection {
  const TidySection(this.title, this.items, {this.keep = const {}});

  final String title;
  final List<ScreenshotItem> items;
  final Set<int> keep;
}

/// 정리 묶음 그리드: 처음엔 [TidySection.keep]을 뺀 전부가 선택돼 있다. 골라서 [휴지통으로 N장] →
/// 되돌리기 스낵바(상세 화면에서 던질 때와 같다). 묶음이 둘 이상이면("한 번에 보기") 묶음별 소제목으로 나눈다.
/// 같은 캡처가 여러 묶음에 있으면 앞 묶음에만 보인다.
class TidyBundleScreen extends StatefulWidget {
  const TidyBundleScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<TidySection> sections;

  @override
  State<TidyBundleScreen> createState() => _TidyBundleScreenState();
}

class _TidyBundleScreenState extends State<TidyBundleScreen> {
  late List<TidySection> _sections = _dedupe(widget.sections);
  late final Set<int> _selected = {
    for (final s in _sections)
      for (final item in s.items)
        if (!s.keep.contains(item.id)) item.id,
  };
  bool _busy = false;
  PeekHandle? _peek;

  /// 손가락이 닿은 캡처의 미리 보기 이미지(디코딩 중이거나 끝난 것). 꾹 누름이 인식되면 이걸로 바로 띄운다.
  (int, PeekImages)? _warm;

  /// 손가락이 닿는 순간 미리 디코딩을 시작한다(탭으로 끝나도 캐시에 남을 뿐이다).
  void _warmUp(ScreenshotItem item) {
    if (_warm?.$1 == item.id) return;
    _warm = (item.id, PeekImages.warm(context, item));
  }

  /// 꾹 누른 썸네일 자리(화면 좌표)에서 미리 보기를 띄운다.
  void _peekAt(ScreenshotItem item) {
    final box =
        _thumbKeys[item.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _closePeek();
    _warmUp(item);
    _peek = showPeek(
      context,
      item,
      box.localToGlobal(Offset.zero) & box.size,
      _warm!.$2,
    );
  }

  void _closePeek() {
    _peek?.close();
    _peek = null;
  }

  final Map<int, GlobalKey> _thumbKeys = {};

  @override
  void dispose() {
    _closePeek();
    super.dispose();
  }

  static List<TidySection> _dedupe(List<TidySection> sections) {
    final seen = <int>{};
    return [
      for (final s in sections)
        TidySection(s.title, [
          for (final item in s.items)
            if (seen.add(item.id)) item,
        ], keep: s.keep),
    ];
  }

  List<ScreenshotItem> get _items => [for (final s in _sections) ...s.items];

  bool get _allSelected => _selected.length == _items.length;

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// 고른 장을 휴지통으로 → 이 화면에서 빼고 → 되돌리기 안내. 다 비면 정리 탭으로 돌아간다.
  Future<void> _trashSelected() async {
    final store = RemineScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final reduced = AppMotion.reduced(context);
    final ids = [
      for (final item in _items)
        if (_selected.contains(item.id)) item.id,
    ];
    if (ids.isEmpty) return;
    final before = _sections;
    setState(() => _busy = true);
    for (final id in ids) {
      await store.trash(id);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sections = [
        for (final s in _sections)
          TidySection(s.title, [
            for (final item in s.items)
              if (!ids.contains(item.id)) item,
          ], keep: s.keep),
      ];
      _selected.removeAll(ids);
    });
    if (_items.isEmpty) navigator.maybePop();

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ids.length}장을 휴지통으로 옮겼어요',
          style: AppText.label.copyWith(color: AppColors.white),
        ),
        duration: AppGesture.undoDuration,
        persist: false,
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkGray,
        shape: const StadiumBorder(),
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.s16,
        ),
        action: SnackBarAction(
          label: '되돌리기',
          textColor: AppColors.lemon,
          onPressed: () => _undo(store, ids, before),
        ),
      ),
      snackBarAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
    );
  }

  /// 되돌리기. 화면이 아직 열려 있으면 묶음을 원래대로(되살린 장은 다시 선택된 채로) 돌린다.
  /// 이미 닫혔으면 저장소만 되돌리고, 정리 탭은 revision으로 다시 센다.
  Future<void> _undo(
    RemineStore store,
    List<int> ids,
    List<TidySection> before,
  ) async {
    for (final id in ids) {
      await store.restore(id);
    }
    if (!mounted) return;
    setState(() {
      _sections = before;
      _selected.addAll(ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                4,
                AppSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  const BackButtonCircle(),
                  Expanded(
                    child: Text(
                      '${widget.title} ${items.length}장',
                      style: AppText.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s12,
                  AppSpacing.screenPadding,
                  AppSpacing.s12,
                ),
                child: _allSelected
                    ? AppButton(
                        label: '선택 해제',
                        outlined: true,
                        onTap: _busy ? null : () => setState(_selected.clear),
                      )
                    : AppButton(
                        label: '전체 선택',
                        outlined: true,
                        onTap: _busy
                            ? null
                            : () => setState(
                                () => _selected.addAll(items.map((s) => s.id)),
                              ),
                      ),
              ),
            Expanded(child: _grid()),
            if (_selected.isNotEmpty) _bar(),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final titled = _sections.length > 1;
    return CustomScrollView(
      slivers: [
        for (final s in _sections)
          if (s.items.isNotEmpty) ...[
            if (titled)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s16,
                  AppSpacing.screenPadding,
                  AppSpacing.s8,
                ),
                sliver: SliverToBoxAdapter(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${s.title} ${s.items.length}장',
                      style: AppText.cardTitle,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.72,
                ),
                itemCount: s.items.length,
                itemBuilder: (_, i) => _tile(s.items[i]),
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s24)),
      ],
    );
  }

  /// 탭은 선택/해제, 꾹 누르면 크게 보기(손 떼면 닫힘). 꾹 누르는 동안엔 선택이 바뀌지 않는다.
  /// [Flutter 메모] 길게 누르기는 [AppTidy.peekPress](0.3초)가 지나야 이긴다. 그 전에 손가락이 움직이면 스크롤이
  /// 이겨서 서로 겹치지 않는다. GestureDetector는 이 시간을 못 바꿔서 RawGestureDetector로 인식기를 직접 단다.
  /// Listener는 경쟁에 끼지 않고 손가락이 닿는 순간만 알려 준다(미리 디코딩 시작).
  Widget _tile(ScreenshotItem item) {
    final on = _selected.contains(item.id);
    return Semantics(
      button: true,
      selected: on,
      label: '${item.category.label} 캡처',
      hint: '길게 눌러 미리 보기',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _warmUp(item),
        child: RawGestureDetector(
          key: ValueKey('tidy-shot-${item.id}'),
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (r) => r.onTap = _busy ? null : () => _toggle(item.id),
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(duration: AppTidy.peekPress),
                  (r) => r
                    ..onLongPressStart = ((_) => _peekAt(item))
                    ..onLongPressEnd = ((_) => _closePeek())
                    ..onLongPressCancel = _closePeek,
                ),
          },
          child: SelectableThumb(
            key: _thumbKeys.putIfAbsent(item.id, GlobalKey.new),
            selected: on,
            child: CaptureThumb(
              key: ValueKey(item.localAssetId),
              assetId: item.localAssetId,
              seed: item.id,
              radius: 12,
              size: 240,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.chip,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Center(
            child: AppButton(
              label: '휴지통으로 ${_selected.length}장',
              dark: true,
              onTap: _busy ? null : _trashSelected,
            ),
          ),
        ),
      ),
    );
  }
}
