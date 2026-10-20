import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/screenshot_item.dart';
import '../widgets/category_sheet.dart';
import '../widgets/home_widgets.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/small_widgets.dart';
import '../widgets/thumb_placeholder.dart';
import 'category_screen.dart';

/// 스크린샷 상세. 들어온 목록(카테고리 전체 또는 선택된 태그로 거른 결과) 안에서 좌우로 넘긴다.
///
/// - 위: 뒤로 + "현재 / 전체" 위치 알약(페이지와 함께 움직이지 않는다)
/// - 가운데: [PageView] — 페이지마다 기울어진 이미지 카드 + 정보 카드(출처·카테고리 칩·요약·태그)
/// - 이미지 카드를 아래로 쓸어내리면 닫힌다(Hero가 그리드의 그 항목으로 돌아간다)
///
/// [Flutter 메모] PageView는 한 화면에 한 페이지씩 좌우로 넘기는 위젯이다. `allowImplicitScrolling`을 켜면
/// 양옆 페이지를 미리 만들어 두어 넘길 때 바로 보인다(3주차 실제 이미지가 오면 여기서 precacheImage).
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.onViewing,
  });

  /// 넘길 수 있는 목록(그리드와 같은 순서).
  final List<ScreenshotItem> items;
  final int initialIndex;

  /// 현재 보는 항목이 바뀔 때마다 id를 알린다(그리드가 그 타일이 보이게 스크롤하도록).
  final ValueChanged<int>? onViewing;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final List<ScreenshotItem> _items = [...widget.items];
  late int _index = widget.initialIndex.clamp(0, _items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    widget.onViewing?.call(_items[i].id);
  }

  /// 카테고리를 바꾸면 이 화면의 항목만 갱신한다(현재 화면 유지). 그리드는 돌아가면 반영된다.
  void _replaceItem(ScreenshotItem updated) {
    final i = _items.indexWhere((s) => s.id == updated.id);
    if (i >= 0) setState(() => _items[i] = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.celadon,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              // 끝에서 멈춘다(첫·마지막 경계).
              physics: const ClampingScrollPhysics(),
              allowImplicitScrolling: true,
              itemCount: _items.length,
              onPageChanged: _onPageChanged,
              findChildIndexCallback: (key) {
                final id = (key as ValueKey<int>).value;
                final i = _items.indexWhere((s) => s.id == id);
                return i < 0 ? null : i;
              },
              itemBuilder: (context, i) => _DetailPage(
                key: ValueKey(_items[i].id),
                item: _items[i],
                isCurrent: i == _index,
                onChanged: _replaceItem,
              ),
            ),
            _TopBar(position: _index + 1, total: _items.length),
          ],
        ),
      ),
    );
  }
}

/// 상단 바가 차지하는 높이(뒤로 버튼 48 + 위 여백 8). 페이지 내용이 그 아래에서 시작하게 한다.
const double _topBarHeight = 56;

/// 상단 바: 뒤로 가기 + "3 / 42" 위치 알약.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.screenPadding,
        0,
      ),
      child: Row(
        children: [
          const BackButtonCircle(background: AppColors.white),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label: '$total장 중 $position번째',
                excludeSemantics: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        '$position / $total',
                        style: AppText.numBadge(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 한 항목의 페이지: 이미지 카드 + 정보 카드. 화면이 낮거나 글자가 크면 이 페이지만 세로로 스크롤된다.
class _DetailPage extends StatefulWidget {
  const _DetailPage({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onChanged,
  });

  final ScreenshotItem item;

  /// 지금 보고 있는 페이지인가. 현재 페이지의 이미지 카드에만 Hero를 건다(이웃 페이지와 태그 중복 방지).
  final bool isCurrent;
  final ValueChanged<ScreenshotItem> onChanged;

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  int _sameInterestCount = 0;
  bool _requested = false;

  ScreenshotItem get _item => widget.item;
  String? get _mainTag => _item.tags.isEmpty ? null : _item.tags.first;

  // InheritedWidget(RemineScope)은 initState가 아니라 didChangeDependencies부터 읽을 수 있다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _loadSameInterest();
    }
  }

  /// "같은 관심사 캡처 N장 더 보기": 대표 태그가 같은 다른 캡처 수.
  Future<void> _loadSameInterest() async {
    final tag = _mainTag;
    if (tag == null) return;
    final page = await RemineScope.of(context).repository
        .list(tag: tag, size: 1);
    if (!mounted) return;
    setState(() => _sameInterestCount = page.totalElements - 1);
  }

  Future<void> _editCategory() async {
    final store = RemineScope.of(context);
    final chosen = await showCategorySheet(
      context,
      current: _item.category,
      autoCategory: _item.autoCategory ?? _item.category,
    );
    if (chosen == null) return;
    final result = await store.changeCategory(_item.id, chosen);
    if (!mounted) return;
    widget.onChanged(
      _item.copyWith(
        category: result.category,
        categorySource: result.categorySource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = _mainTag;
    return LayoutBuilder(
      builder: (context, box) {
        // 이미지 영역 높이는 화면 높이에 비례(240~460). 글자가 들어가지 않아 내용과 무관하게 정할 수 있다.
        final imageAreaHeight = (box.maxHeight * 0.46).clamp(240.0, 460.0);
        // 스크롤 안 Column은 높이가 무한이라 Expanded를 못 쓴다. 최소 높이 = 화면 높이로 두고 spaceBetween으로
        // 세 묶음(상단 여백 / 이미지 / 정보 카드) 사이에 남는 높이를 나눈다 → 이미지 카드가 남는 공간의 가운데에 놓인다.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: _topBarHeight),
                SizedBox(
                  key: ValueKey('image-area-${_item.id}'),
                  height: imageAreaHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s16,
                    ),
                    child: _ThrowCard(
                      item: _item,
                      tag: tag,
                      isCurrent: widget.isCurrent,
                    ),
                  ),
                ),
                _InfoCard(
                  item: _item,
                  sameInterestCount: _sameInterestCount,
                  onEditCategory: _editCategory,
                  onMore: tag == null
                      ? null
                      : () => Navigator.of(context).push(
                          appRoute(
                            context,
                            (_) => CategoryScreen(
                              category: _item.category,
                              initialTag: tag,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 기울어진 흰 이미지 카드(플레이스홀더) + #태그 스티커. 현재 페이지에서는 Hero로 그리드 썸네일과 이어진다.
/// 크기는 주어진 영역(세로·가로)을 넘지 않게 비율 0.62로 맞추고, 안쪽 막대는 카드 크기에 비례한다.
///
/// 세로 제스처는 이 카드에만 건다(정보 카드의 세로 스크롤·좌우 넘기기와 겹치지 않게):
/// 아래로 쓸어내리면 닫힌다.
class _ThrowCard extends StatefulWidget {
  const _ThrowCard({
    required this.item,
    required this.tag,
    required this.isCurrent,
  });

  final ScreenshotItem item;
  final String? tag;
  final bool isCurrent;

  @override
  State<_ThrowCard> createState() => _ThrowCardState();
}

class _ThrowCardState extends State<_ThrowCard> with TickerProviderStateMixin {
  // 드래그로 움직인 세로 거리(아래가 +). 스프링 복귀 때는 이 컨트롤러 값이 곧 dy다.
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _dy = _spring.value));
  double _dy = 0;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  double get _screenHeight => MediaQuery.sizeOf(context).height;

  void _onDragStart(DragStartDetails d) {
    _spring.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (AppMotion.reduced(context)) {
      _dy += d.delta.dy; // 효과는 없지만 놓을 때 판단에 쓴다
      return;
    }
    setState(() => _dy += d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dismissDistance = _screenHeight * AppGesture.dismissFraction;
    if (_dy > 0 &&
        (_dy >= dismissDistance || v >= AppGesture.dismissFlingVelocity)) {
      Navigator.of(context).maybePop(); // Hero가 이 항목의 그리드 썸네일로 돌아간다
      return;
    }
    _springBack(v);
  }

  void _springBack(double velocity) {
    if (AppMotion.reduced(context) || _dy == 0) {
      setState(() => _dy = 0);
      return;
    }
    _spring.value = _dy;
    _spring.animateWith(SpringSimulation(AppMotion.spring, _dy, 0, velocity));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (_, block) = ThumbPlaceholder.colorsFor(item.id);
    final visualDy = AppMotion.reduced(context) ? 0.0 : _dy;
    // 아래로 끌수록 살짝 줄어든다.
    final down = (visualDy / (_screenHeight * AppGesture.dismissFraction))
        .clamp(0.0, 1.0);
    final scale = visualDy > 0 ? 1 - 0.08 * down : 1.0;

    final card = ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          var width = box.maxHeight * 0.62;
          if (width > box.maxWidth * 0.68) width = box.maxWidth * 0.68;
          final visual = Transform.rotate(
            angle: decorAngle(item.id, max: 0.07),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Padding(
                padding: EdgeInsets.all(width * 0.07),
                child: _CardContent(block: block),
              ),
            ),
          );
          return Center(
            child: SizedBox(
              width: width,
              height: width / 0.62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: widget.isCurrent
                        ? Hero(tag: 'screenshot-${item.id}', child: visual)
                        : visual,
                  ),
                  if (widget.tag != null)
                    Positioned(
                      top: -10,
                      right: -14,
                      child: Sticker(label: '#${widget.tag}', angle: 0.1),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: widget.isCurrent ? _onDragStart : null,
      onVerticalDragUpdate: widget.isCurrent ? _onDragUpdate : null,
      onVerticalDragEnd: widget.isCurrent ? _onDragEnd : null,
      child: Transform.translate(
        offset: Offset(0, visualDy),
        child: Transform.scale(scale: scale, child: card),
      ),
    );
  }
}

/// 이미지 카드 안쪽(가짜 화면): 큰 블록 + 글자 막대들. 막대는 카드 폭 비율이고, 카드가 낮으면 블록만 남긴다.
class _CardContent extends StatelessWidget {
  const _CardContent({required this.block});

  final Color block;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final showBars = box.maxHeight >= 150;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: block.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (showBars) ...[
              const SizedBox(height: AppSpacing.s12),
              _bar(1.0, AppColors.chip),
              const SizedBox(height: AppSpacing.s8),
              _bar(0.6, AppColors.chip),
              const SizedBox(height: AppSpacing.s8),
              _bar(0.3, AppColors.border),
              const SizedBox(height: AppSpacing.s12),
              _bar(1.0, AppColors.darkGray, height: 28),
            ],
          ],
        );
      },
    );
  }

  Widget _bar(double widthFactor, Color color, {double height = 10}) =>
      FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.item,
    required this.sameInterestCount,
    required this.onEditCategory,
    required this.onMore,
  });

  final ScreenshotItem item;
  final int sameInterestCount;
  final VoidCallback onEditCategory;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final source = [
      if (item.sourceApp != null) item.sourceApp!,
      formatStamp(item.takenAt),
    ].join(' · ');
    return DecoratedBox(
      key: ValueKey('info-card-${item.id}'),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.card + 4),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 출처 글자는 남는 폭 안에서 줄바꿈·말줄임, 카테고리 칩도 폭이 모자라면 줄어든다.
                  Expanded(
                    child: Text(
                      source,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Flexible(
                    child: PressableScale(
                      key: ValueKey('category-chip-${item.id}'),
                      onTap: onEditCategory,
                      label: '카테고리 ${item.category.label}, 눌러서 수정',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: AppChip.outlined(
                            label: item.category.label,
                            leading: Icon(
                              categoryIcon(item.category),
                              size: 16,
                              color: AppColors.ink,
                            ),
                            trailing: const Icon(
                              LucideIcons.pencil,
                              size: 14,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                item.summary ?? item.category.label,
                style: AppText.cardTitle,
              ),
              const SizedBox(height: AppSpacing.s16),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final t in item.tags) AppChip.hashtag(label: '#$t'),
                ],
              ),
              if (onMore != null && sameInterestCount > 0) ...[
                const SizedBox(height: AppSpacing.s20),
                PressableScale(
                  onTap: onMore,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.lemon,
                        borderRadius: BorderRadius.circular(AppRadii.tile),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '같은 관심사 캡처 $sameInterestCount장 더 보기',
                                style: AppText.label.copyWith(fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            const Icon(
                              LucideIcons.arrowRight,
                              size: 20,
                              color: AppColors.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
