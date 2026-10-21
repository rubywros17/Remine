import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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
/// - 이미지 카드를 **아래로** 쓸어내리면 닫히고(Hero가 그리드의 그 항목으로 돌아간다),
///   **위로 던지면** 휴지통으로 간다(시그니처 모션, 값은 [AppGesture], 명세는 docs/design.md).
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

/// 위로 끄는 진행도(0~1.15, 1이 기준선)와 기준선 통과 여부. 오버레이(배경·휴지통 아이콘)가 이 값을 따라간다.
typedef _ThrowView = (double progress, bool pastLine);

class _DetailScreenState extends State<DetailScreen> {
  late final List<ScreenshotItem> _items = [...widget.items];
  late int _index = widget.initialIndex.clamp(0, _items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);

  /// 끄는 동안의 진행도. 값이 바뀌어도 페이지 전체를 다시 만들지 않도록 ValueNotifier로 따로 둔다.
  final ValueNotifier<_ThrowView> _view = ValueNotifier((0.0, false));

  /// 메뉴("⋯ → 휴지통으로")가 현재 카드를 위로 날려 보낼 수 있도록 카드 State에 닿는 키.
  final Map<int, GlobalKey<_ThrowCardState>> _cardKeys = {};

  /// 휴지통 처리 뒤 새로 나타난 항목의 도착 애니메이션을 한 번 재생하기 위한 표시.
  int? _arrivalId;
  int _arrivalToken = 0;

  @override
  void dispose() {
    _pages.dispose();
    _view.dispose();
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

  /// 휴지통 처리: 저장소에 반영 → 이 목록에서 제거 → 다음 항목(마지막이었으면 이전 항목)으로 → 되돌리기 안내.
  /// 목록이 비면 그리드로 돌아간다.
  Future<void> _trash(ScreenshotItem item) async {
    final store = RemineScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final reduced = AppMotion.reduced(context);
    final index = _items.indexWhere((s) => s.id == item.id);
    if (index < 0) return;

    await store.trash(item.id);
    if (!mounted) return;
    _view.value = (0.0, false);

    final removed = _items[index];
    final wasLast = index == _items.length - 1;
    setState(() {
      _items.removeAt(index);
      _cardKeys.remove(removed.id);
      if (_items.isNotEmpty) {
        _index = wasLast ? _items.length - 1 : index;
        if (!wasLast) {
          _arrivalId = _items[_index].id;
          _arrivalToken++;
        }
      }
    });

    if (_items.isEmpty) {
      navigator.maybePop(); // 목록이 비면 그리드로
    } else {
      widget.onViewing?.call(_items[_index].id);
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '휴지통으로 옮겼어',
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
          onPressed: () => _undo(store, removed, index),
        ),
      ),
      // 애니메이션 줄이기: 스낵바도 효과 없이 바로 나타나고 사라진다.
      snackBarAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
    );
  }

  /// 되돌리기. 이 화면이 아직 열려 있으면 원래 위치에 다시 끼우고 그 페이지로 이동한다.
  /// 이미 닫혔으면(목록이 비어 그리드로 나간 경우) 저장소만 복원하고 그리드는 revision으로 갱신된다.
  Future<void> _undo(
    RemineStore store,
    ScreenshotItem removed,
    int index,
  ) async {
    await store.restore(removed.id);
    if (!mounted) return;
    final at = index.clamp(0, _items.length);
    setState(() {
      _items.insert(at, removed);
      _index = at;
    });
    widget.onViewing?.call(removed.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(at);
    });
  }

  /// "⋯ → 휴지통으로": 카드가 위로 빨려 들어가는 같은 동작(애니메이션 줄이기면 즉시 처리).
  void _requestTrash(ScreenshotItem item) {
    final card = _cardKeys[item.id]?.currentState;
    if (card != null) {
      card.flyToTrash();
    } else {
      _trash(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.celadon,
      // 배경은 끄는 거리에 비례해 다크그레이로 어두워진다(최대 불투명도는 AppGesture.trashDimMaxOpacity).
      body: ValueListenableBuilder<_ThrowView>(
        valueListenable: _view,
        builder: (context, view, child) {
          final dim = view.$1.clamp(0.0, 1.0) * AppGesture.trashDimMaxOpacity;
          return ColoredBox(
            color: Color.alphaBlend(
              AppColors.darkGray.withValues(alpha: dim),
              AppColors.celadon,
            ),
            child: child,
          );
        },
        child: SafeArea(
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
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return _DetailPage(
                    key: ValueKey(item.id),
                    item: item,
                    isCurrent: i == _index,
                    cardKey: _cardKeys.putIfAbsent(item.id, GlobalKey.new),
                    view: _view,
                    arriveToken: item.id == _arrivalId ? _arrivalToken : 0,
                    onChanged: _replaceItem,
                    onTrash: () => _trash(item),
                    onRequestTrash: () => _requestTrash(item),
                  );
                },
              ),
              _TopBar(position: _index + 1, total: _items.length),
              _TrashTarget(view: _view),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상단 바가 차지하는 높이(뒤로 버튼 48 + 위 여백 8). 페이지 내용이 그 아래에서 시작하게 한다.
const double _topBarHeight = 56;

/// 휴지통 아이콘의 중심 y(화면 안전 영역 위쪽 기준). 카드가 빨려 들어가는 목적지이기도 하다.
const double _trashIconCenterY = 8 + 28;

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
      // 높이를 48로 고정하지 않으면 Expanded 안의 Align이 세로로도 늘어나 바가 화면 전체 높이가 된다.
      child: SizedBox(
        height: 48,
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
      ),
    );
  }
}

/// 화면 상단 중앙의 휴지통 아이콘. 위로 끌수록 커지고, 기준선을 넘으면 검은 원 + 레몬 아이콘으로 강조된다.
/// 끌지 않을 때(그리고 애니메이션 줄이기일 때)는 보이지 않는다.
class _TrashTarget extends StatelessWidget {
  const _TrashTarget({required this.view});

  final ValueListenable<_ThrowView> view;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: _trashIconCenterY - 28,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ValueListenableBuilder<_ThrowView>(
            valueListenable: view,
            builder: (context, v, _) {
              final t = v.$1.clamp(0.0, 1.0);
              if (t <= 0.01) return const SizedBox(height: 56);
              final scale = lerpDouble(
                AppGesture.trashIconMinScale,
                AppGesture.trashIconMaxScale,
                t,
              )!;
              return Center(
                child: Opacity(
                  opacity: t,
                  // 기준선을 넘으면 살짝 더 커지며 강조(짧은 보간).
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: v.$2 ? 1.18 : 1.0),
                    duration: AppMotion.duration(context, MotionDuration.fast),
                    curve: AppMotion.standard,
                    builder: (context, pop, child) =>
                        Transform.scale(scale: scale * pop, child: child),
                    child: DecoratedBox(
                      key: const ValueKey('trash-target'),
                      decoration: BoxDecoration(
                        color: v.$2
                            ? AppColors.trashActiveBackground
                            : AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Icon(
                          LucideIcons.trash2,
                          size: 26,
                          color: v.$2
                              ? AppColors.trashActiveIcon
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
    required this.cardKey,
    required this.view,
    required this.arriveToken,
    required this.onChanged,
    required this.onTrash,
    required this.onRequestTrash,
  });

  final ScreenshotItem item;

  /// 지금 보고 있는 페이지인가. 현재 페이지의 이미지 카드에만 Hero를 건다(이웃 페이지와 태그 중복 방지).
  final bool isCurrent;
  final GlobalKey<_ThrowCardState> cardKey;
  final ValueNotifier<_ThrowView> view;
  final int arriveToken;
  final ValueChanged<ScreenshotItem> onChanged;
  final Future<void> Function() onTrash;
  final VoidCallback onRequestTrash;

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
                      key: widget.cardKey,
                      item: _item,
                      tag: tag,
                      isCurrent: widget.isCurrent,
                      view: widget.view,
                      arriveToken: widget.arriveToken,
                      onTrash: widget.onTrash,
                    ),
                  ),
                ),
                _InfoCard(
                  item: _item,
                  sameInterestCount: _sameInterestCount,
                  onEditCategory: _editCategory,
                  onTrash: widget.onRequestTrash,
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
/// - 아래로 쓸어내리면 닫힌다.
/// - 위로 끌면 카드가 손가락을 따라 올라가고(축소·기울어짐), 배경이 어두워지며 휴지통 아이콘이 커진다.
///   기준선(화면 높이 1/3) 또는 위쪽 속도 임계값을 넘겨 놓으면 휴지통으로 빨려 들어간다. 모자라면 스프링으로 복귀.
class _ThrowCard extends StatefulWidget {
  const _ThrowCard({
    super.key,
    required this.item,
    required this.tag,
    required this.isCurrent,
    required this.view,
    required this.onTrash,
    this.arriveToken = 0,
  });

  final ScreenshotItem item;
  final String? tag;
  final bool isCurrent;
  final ValueNotifier<_ThrowView> view;

  /// 카드가 휴지통에 빨려 들어간 뒤(또는 줄이기 모드에서 바로) 호출되어 실제 처리를 맡긴다.
  final Future<void> Function() onTrash;

  /// 값이 바뀌면 도착 애니메이션(살짝 커지며 나타남)을 한 번 재생한다. 휴지통 처리 뒤 새로 보이는 항목용.
  final int arriveToken;

  @override
  State<_ThrowCard> createState() => _ThrowCardState();
}

class _ThrowCardState extends State<_ThrowCard> with TickerProviderStateMixin {
  // 드래그로 움직인 세로 거리(아래가 +). 스프링 복귀 때는 이 컨트롤러 값이 곧 dy다.
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onSpring);
  // 휴지통으로 빨려 들어가는 애니메이션(0 → 1).
  late final AnimationController _fly = AnimationController(vsync: this)
    ..addListener(() => setState(() {}));
  // 휴지통 처리 뒤 새로 나타난 카드의 도착(0 → 1).
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    value: 1,
  )..addListener(() => setState(() {}));

  double _dy = 0;
  bool _past = false; // 기준선을 넘은 상태(햅틱을 한 번만 울리기 위해)
  bool _flying = false;
  Offset _flyTarget = Offset.zero;
  double _flyStartDy = 0;
  double _flyStartScale = 1;

  @override
  void didUpdateWidget(covariant _ThrowCard old) {
    super.didUpdateWidget(old);
    if (widget.arriveToken != old.arriveToken &&
        widget.arriveToken != 0 &&
        !AppMotion.reduced(context)) {
      _arrive.duration = AppMotion.duration(context, MotionDuration.base);
      _arrive.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    _fly.dispose();
    _arrive.dispose();
    super.dispose();
  }

  double get _screenHeight => MediaQuery.sizeOf(context).height;
  double get _line => _screenHeight * AppGesture.trashLineFraction;
  double get _upProgress => (-_dy / _line).clamp(0.0, 1.15);

  void _publish() =>
      widget.view.value = (_dy < -0.5 ? _upProgress : 0.0, _past);

  void _onSpring() {
    setState(() => _dy = _spring.value);
    _past = _upProgress >= 1;
    _publish();
    // 스프링이 거의 멈추면 정확히 제자리로 맞춘다(아주 작은 잔여 오프셋·아이콘 표시 방지).
    if (_dy.abs() < 0.5 && !_spring.isAnimating) {
      _dy = 0;
    }
  }

  void _onDragStart(DragStartDetails d) {
    if (_flying) return;
    _spring.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flying) return;
    if (AppMotion.reduced(context)) {
      _dy += d.delta.dy; // 효과는 없지만 놓을 때 판단에 쓴다
      return;
    }
    setState(() => _dy += d.delta.dy);
    final nowPast = _dy < 0 && _upProgress >= 1;
    if (nowPast && !_past) {
      HapticFeedback.mediumImpact(); // 기준선을 넘는 순간 한 번
    }
    _past = nowPast;
    _publish();
  }

  void _onDragEnd(DragEndDetails d) {
    if (_flying) return;
    final v = d.primaryVelocity ?? 0; // 위로 갈수록 음수(px/s)
    final up = -_dy;
    final trash =
        _dy < 0 &&
        (up >= _line ||
            (v <= -AppGesture.trashFlingVelocity &&
                up >= AppGesture.trashFlingMinDistance));
    final dismissDistance = _screenHeight * AppGesture.dismissFraction;
    final dismiss =
        _dy > 0 &&
        (_dy >= dismissDistance || v >= AppGesture.dismissFlingVelocity);

    if (trash) {
      _commitTrash();
    } else if (dismiss) {
      Navigator.of(context).maybePop(); // Hero가 이 항목의 그리드 썸네일로 돌아간다
    } else {
      _springBack(v);
    }
  }

  void _springBack(double velocity) {
    _past = false;
    if (AppMotion.reduced(context) || _dy == 0) {
      setState(() => _dy = 0);
      _publish();
      return;
    }
    _spring.value = _dy;
    _spring.animateWith(SpringSimulation(AppMotion.spring, _dy, 0, velocity));
  }

  /// 기준선을 넘겨 놓았을 때(또는 메뉴에서 호출): 휴지통으로 처리한다.
  void _commitTrash() {
    if (AppMotion.reduced(context)) {
      // 애니메이션 줄이기: 효과 없이 바로 처리
      _dy = 0;
      _past = false;
      widget.onTrash();
      return;
    }
    _startFly();
  }

  /// 정보 카드의 "⋯ → 휴지통으로": 같은 동작을 제스처 없이 실행한다.
  Future<void> flyToTrash() async {
    if (_flying) return;
    _dy = 0;
    _commitTrash();
  }

  /// 카드가 휴지통 아이콘 위치로 빨려 들어간다(축소·투명화). 끝나면 실제 처리를 맡기고 아이콘을 숨긴다.
  Future<void> _startFly() async {
    final box = context.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final size = MediaQuery.sizeOf(context);
    final target = Offset(
      size.width / 2,
      MediaQuery.paddingOf(context).top + _trashIconCenterY,
    );
    _spring.stop();
    _flyTarget = target - center;
    _flyStartDy = _dy;
    _flyStartScale = _scaleFor(_dy);
    _flying = true;
    // 아이콘은 강조된 채로 유지한다.
    widget.view.value = (1.15, true);
    _fly.duration = AppMotion.duration(context, MotionDuration.slow);
    await _fly.forward(from: 0);
    if (!mounted) return;
    await widget.onTrash();
    if (!mounted) return;
    // 카드가 그대로 남아 있다면(처리 실패 등) 원래대로 돌려놓는다.
    setState(() {
      _flying = false;
      _dy = 0;
      _past = false;
    });
    _publish();
  }

  double _scaleFor(double dy) {
    if (dy < 0) {
      final t = (-dy / _line).clamp(0.0, 1.0);
      return lerpDouble(1, AppGesture.trashCardMinScale, t)!;
    }
    final down = (dy / (_screenHeight * AppGesture.dismissFraction)).clamp(
      0.0,
      1.0,
    );
    return 1 - 0.08 * down;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (_, block) = ThumbPlaceholder.colorsFor(item.id);
    final reduced = AppMotion.reduced(context);

    // 화면에 보이는 변형(이동·축소·기울기·투명도). 줄이기 모드에서는 항상 제자리.
    var dx = 0.0, dy = 0.0, scale = 1.0, angle = 0.0, opacity = 1.0;
    if (!reduced) {
      if (_flying) {
        final p = AppMotion.emphasized.transform(_fly.value);
        dx = lerpDouble(0, _flyTarget.dx, p)!;
        dy = lerpDouble(_flyStartDy, _flyTarget.dy, p)!;
        scale = lerpDouble(_flyStartScale, AppGesture.trashSuckScale, p)!;
        angle = -AppGesture.trashCardTilt;
        opacity = 1 - p;
      } else {
        dy = _dy;
        scale = _scaleFor(_dy);
        if (_dy < 0) {
          angle = -AppGesture.trashCardTilt * (-_dy / _line).clamp(0.0, 1.0);
        }
      }
      // 새로 나타난 카드: 살짝 작은 상태에서 커지며 나타난다.
      final a = Curves.easeOutCubic.transform(_arrive.value);
      scale *= lerpDouble(0.92, 1, a)!;
      opacity *= lerpDouble(0.4, 1, a)!;
    }

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
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: card),
          ),
        ),
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

enum _CardAction { trash }

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.item,
    required this.sameInterestCount,
    required this.onEditCategory,
    required this.onTrash,
    required this.onMore,
  });

  final ScreenshotItem item;
  final int sameInterestCount;
  final VoidCallback onEditCategory;

  /// "⋯ → 휴지통으로" (위로 던지는 제스처와 같은 동작. 제스처가 어려운 사용자를 위한 대체 경로)
  final VoidCallback onTrash;
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
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
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
                  PopupMenuButton<_CardAction>(
                    key: ValueKey('more-menu-${item.id}'),
                    tooltip: '더 보기 메뉴',
                    icon: const Icon(
                      LucideIcons.ellipsis,
                      size: 22,
                      color: AppColors.ink,
                    ),
                    color: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    popUpAnimationStyle: AppMotion.reduced(context)
                        ? AnimationStyle.noAnimation
                        : null,
                    onSelected: (_) => onTrash(),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _CardAction.trash,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.trash2,
                              size: 18,
                              color: AppColors.ink,
                            ),
                            const SizedBox(width: AppSpacing.s12),
                            Text('휴지통으로', style: AppText.label),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        for (final t in item.tags)
                          AppChip.hashtag(label: '#$t'),
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
                              borderRadius: BorderRadius.circular(
                                AppRadii.tile,
                              ),
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
                                      style: AppText.label.copyWith(
                                        fontSize: 15,
                                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
