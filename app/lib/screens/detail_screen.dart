import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/remine_store.dart';
import '../data/remote/api_client.dart' show ApiException;
import '../models/category.dart';
import '../models/category_update.dart';
import '../models/screenshot_item.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/category_sheet.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/small_widgets.dart';
import '../widgets/thumb_placeholder.dart';
import 'category_screen.dart';
import 'photo_viewer_screen.dart';

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

/// 이미지 카드의 화면 읽기용 동작(보이는 UI 없음). 라벨은 스크린 리더가 동작 목록에서 읽는다.
const trashSemanticsAction = CustomSemanticsAction(label: '휴지통으로 옮기기');

/// 사진 비율을 모를 때 쓰는 이미지 카드 기본 비율(폭/높이).
const double detailCardDefaultAspect = 0.62;

/// 영역([areaWidth] × [areaHeight]) 안에 들어가는 **가장 큰** 이미지 카드의 바깥 폭.
///
/// 폭은 영역 폭의 78%([AppDetail.cardMaxWidthFraction])까지, 높이는 영역 높이까지이고 사진 비율([aspect], 폭/높이)을 지킨다.
/// 흰 테두리는 두께가 고정(6px)이라 테두리를 포함한 카드 높이는 `(폭 − 12) / 비율 + 12`다.
/// 세로로 긴 사진은 높이 기준으로 폭이 정해지고, 안쪽 사진 영역의 비율이 사진과 같아 `cover`로 그려도 잘리지 않는다.
double detailCardWidth({
  required double areaWidth,
  required double areaHeight,
  double? aspect,
}) {
  final a = (aspect ?? detailCardDefaultAspect).clamp(0.2, 5.0);
  final border2 = AppDetail.cardBorder * 2;
  final byWidth = areaWidth * AppDetail.cardMaxWidthFraction;
  final byHeight = (areaHeight - border2) * a + border2;
  final width = byWidth < byHeight ? byWidth : byHeight;
  return width < border2 + 1 ? border2 + 1 : width;
}

/// [detailCardWidth]로 정한 폭의 카드 바깥 높이(테두리 포함).
double detailCardHeight(double width, {double? aspect}) {
  final a = (aspect ?? detailCardDefaultAspect).clamp(0.2, 5.0);
  final border2 = AppDetail.cardBorder * 2;
  return (width - border2) / a + border2;
}

class _DetailScreenState extends State<DetailScreen> {
  late final List<ScreenshotItem> _items = [...widget.items];
  late int _index = widget.initialIndex.clamp(0, _items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);

  /// 끄는 동안의 진행도. 값이 바뀌어도 페이지 전체를 다시 만들지 않도록 ValueNotifier로 따로 둔다.
  final ValueNotifier<_ThrowView> _view = ValueNotifier((0.0, false));

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
          '휴지통으로 옮겼어요',
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
                    view: _view,
                    arriveToken: item.id == _arrivalId ? _arrivalToken : 0,
                    onChanged: _replaceItem,
                    onTrash: () => _trash(item),
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
    required this.view,
    required this.arriveToken,
    required this.onChanged,
    required this.onTrash,
  });

  final ScreenshotItem item;

  /// 지금 보고 있는 페이지인가. 현재 페이지의 이미지 카드에만 Hero를 건다(이웃 페이지와 태그 중복 방지).
  final bool isCurrent;
  final ValueNotifier<_ThrowView> view;
  final int arriveToken;
  final ValueChanged<ScreenshotItem> onChanged;
  final Future<void> Function() onTrash;

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
    if (_item.id < 0) return; // 버튼이 막혀 있지만, 다른 경로로 불려도 터지지 않게 한다
    final store = RemineScope.of(context);
    final chosen = await showCategorySheet(
      context,
      current: _item.category,
      autoCategory: _item.autoCategory ?? _item.category,
    );
    if (chosen == null) return;
    final CategoryUpdate result;
    try {
      result = await store.changeCategory(_item.id, chosen);
    } on ApiException {
      // 서버에 닿지 못했다. 화면은 그대로 두고 안내만 한다(바뀐 척하지 않는다).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카테고리를 바꾸지 못했어요. 연결을 확인하고 다시 해 주세요.')),
      );
      return;
    }
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
        // 이미지 영역은 상단 바와 정보 카드 사이의 **남는 높이를 모두** 차지한다(최소 240, 모자라면 페이지가 스크롤).
        // 스크롤 안 Column은 높이가 무한이라 Expanded를 못 쓴다 → 최소 높이 = 화면 높이로 두고 IntrinsicHeight로
        // 정보 카드의 고유 높이를 먼저 정한 뒤, 남는 높이를 Expanded(이미지 영역)에 준다.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: _topBarHeight),
                  Expanded(
                    key: ValueKey('image-area-${_item.id}'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 240),
                      // IntrinsicHeight는 자식의 고유 높이를 묻는데 LayoutBuilder(카드)는 대답하지 못한다.
                      // 그래서 고유 높이를 묻지 않고 영역을 그대로 채우는 레이아웃으로 한 번 감싼다.
                      child: CustomSingleChildLayout(
                        delegate: const _FillAreaDelegate(),
                        child: Padding(
                          // 상단 바 아래 최소 16px 여백, 아래는 정보 카드와 붙지 않게 8px.
                          padding: const EdgeInsets.only(
                            top: AppDetail.cardTopGap,
                            bottom: AppSpacing.s8,
                          ),
                          child: _ThrowCard(
                            item: _item,
                            isCurrent: widget.isCurrent,
                            view: widget.view,
                            arriveToken: widget.arriveToken,
                            onTrash: widget.onTrash,
                          ),
                        ),
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
          ),
        );
      },
    );
  }
}

/// 주어진 제약을 그대로 채우고 자식에게도 그 제약을 준다. [SizedBox.expand]와 같지만 고유 높이를 묻지 않아
/// [IntrinsicHeight] 안에서도 안전하다.
class _FillAreaDelegate extends SingleChildLayoutDelegate {
  const _FillAreaDelegate();

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints;

  @override
  bool shouldRelayout(covariant _FillAreaDelegate old) => false;
}

/// 기울어진 흰 이미지 카드(플레이스홀더) + #태그 스티커. 현재 페이지에서는 Hero로 그리드 썸네일과 이어진다.
/// 크기는 [detailCardWidth] 규칙: 영역 안에서 **사진의 실제 비율**을 지키는 가장 큰 카드(폭은 영역의 86%까지).
/// 비율을 모르면 0.62. 가짜 데이터 모드의 안쪽 막대는 카드 크기에 비례한다.
///
/// 세로 제스처는 이 카드에만 건다(정보 카드의 세로 스크롤·좌우 넘기기와 겹치지 않게):
/// - 아래로 쓸어내리면 닫힌다.
/// - 위로 끌면 카드가 손가락을 따라 올라가고(축소·기울어짐), 배경이 어두워지며 휴지통 아이콘이 커진다.
///   기준선(화면 높이 1/3) 또는 위쪽 속도 임계값을 넘겨 놓으면 휴지통으로 빨려 들어간다. 모자라면 스프링으로 복귀.
class _ThrowCard extends StatefulWidget {
  const _ThrowCard({
    required this.item,
    required this.isCurrent,
    required this.view,
    required this.onTrash,
    this.arriveToken = 0,
  });

  final ScreenshotItem item;
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

  /// 사진의 실제 폭/높이 비율. 읽어 오기 전·못 읽으면 null → 기본 비율로 그린다(가짜 데이터 모드는 항상 null).
  double? _aspect;
  String? _aspectFor;

  // InheritedWidget(DeviceScope)은 initState가 아니라 didChangeDependencies부터 읽을 수 있다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reader = DeviceScope.maybeOf(context)?.reader;
    final id = widget.item.localAssetId;
    if (reader != null && _aspectFor != id) {
      _aspectFor = id;
      reader
          .aspectRatio(id)
          .then((a) {
            if (mounted && a != null && a != _aspect) {
              setState(() => _aspect = a);
            }
          })
          .catchError((_) {}); // 비율을 못 읽어도 기본 비율로 그린다
    }
  }

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

  /// 이미지를 누르면 전체 화면 보기(확대·축소, 아래로 쓸거나 X로 닫기). 던지는 중에는 열지 않는다.
  void _openViewer() {
    if (_flying || _dy != 0) return;
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => PhotoViewerScreen(
          assetId: widget.item.localAssetId,
          seed: widget.item.id,
        ),
      ),
    );
  }

  /// 이미지 카드의 화면 읽기용 동작 "휴지통으로 옮기기": 위로 던지는 것과 같은 동작을 제스처 없이 실행한다.
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
          // 영역 안에서 사진 비율을 지키는 가장 큰 카드. 세로로 긴 사진이면 높이 기준으로 폭이 정해진다.
          final width = detailCardWidth(
            areaWidth: box.maxWidth,
            areaHeight: box.maxHeight,
            aspect: _aspect,
          );
          final visual = Transform.rotate(
            angle: AppDetail
                .cardTilt, // 가만히 있을 때 -2°. 드래그 중에는 바깥 Transform이 더 기울인다.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.cardShadow,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppDetail.cardBorder),
                child: _CardContent(item: item, block: block, aspect: _aspect),
              ),
            ),
          );
          return Center(
            child: SizedBox(
              width: width,
              height: detailCardHeight(width, aspect: _aspect),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: widget.isCurrent
                        ? Hero(tag: 'screenshot-${item.id}', child: visual)
                        : visual,
                  ),
                  // 카드 위 스티커는 태그가 아니라 카테고리(아이콘 + 이름, 레몬). 태그는 아래 정보 카드의 칩으로 그대로 있다.
                  Positioned(
                    top: -10,
                    right: -14,
                    child: _CategorySticker(category: item.category),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // 화면 읽기(TalkBack 등) 전용 동작. 화면에 보이는 버튼은 없다 — 삭제는 위로 던지기뿐이고,
    // 스크린 리더 사용자는 이미지 카드의 동작 목록에서 같은 동작을 고른다.
    return Semantics(
      container: true,
      label: '캡처 이미지',
      onTap: widget.isCurrent ? _openViewer : null, // 전체 화면 보기
      customSemanticsActions: widget.isCurrent && !_flying
          ? {trashSemanticsAction: () => flyToTrash()}
          : const {},
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.isCurrent ? _openViewer : null,
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
      ),
    );
  }
}

/// 이미지 카드 안쪽. 기기 모드에서는 **기기 사진**(없으면 "사진이 없어요" 자리 표시)이 카드를 채운다.
/// 가짜 데이터 모드(크롬·테스트)에서는 큰 블록 + 글자 막대들이다. 막대는 카드 폭 비율이고, 카드가 낮으면 블록만 남긴다.
class _CardContent extends StatelessWidget {
  const _CardContent({required this.item, required this.block, this.aspect});

  final ScreenshotItem item;
  final Color block;

  /// 사진의 폭/높이 비율(알 때만). 썸네일을 이 비율로 받아 카드에 사진 전체가 보이게 한다.
  final double? aspect;

  @override
  Widget build(BuildContext context) {
    if (DeviceScope.maybeOf(context) != null) {
      return CaptureThumb(
        assetId: item.localAssetId,
        seed: item.id,
        radius: AppRadii.tile,
        size: 720,
        aspect: aspect,
      );
    }
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

/// 기기에서 분류한 캡처(음수 id)의 카테고리 수정 버튼이 막힌 이유.
const deviceClassifiedNotice = '기기에서 분류한 캡처라 아직 바꿀 수 없어요';

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
                  // 칩은 자기 크기대로 오른쪽 끝에 붙는다(폭이 모자라면 화면 폭의 절반까지만 커진다).
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.5,
                    ),
                    child: PressableScale(
                      key: ValueKey('category-chip-${item.id}'),
                      // 기기에서 분류한 캡처(id < 0)는 아직 서버에 없어 수정할 수 없다 → 비활성화.
                      onTap: item.id < 0 ? null : onEditCategory,
                      label: item.id < 0
                          ? '카테고리 ${item.category.label}, $deviceClassifiedNotice'
                          : '카테고리 ${item.category.label}, 눌러서 수정',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        // widthFactor: 1 — 칸을 칩 폭에만 맞춘다(없으면 가용 폭 전체로 늘어나 칩이 가운데에 뜬다).
                        child: Center(
                          widthFactor: 1,
                          child: AppChip(
                            background: AppColors.lemon, // 레몬 알약(테두리 없음) + 연필
                            label: item.category.label,
                            leading: Icon(
                              categoryIcon(item.category),
                              size: 16,
                              color: AppColors.ink,
                            ),
                            trailing: item.id < 0
                                ? null
                                : const Icon(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.id < 0) ...[
                    Text(deviceClassifiedNotice, style: AppText.caption),
                  ],
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 이미지 카드 위의 카테고리 스티커(아이콘 + 이름, 레몬 배경). 카드 오른쪽 위에 살짝 기울여 붙는다.
class _CategorySticker extends StatelessWidget {
  const _CategorySticker({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.lemon,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(categoryIcon(category), size: 14, color: AppColors.ink),
              const SizedBox(width: 6),
              Text(category.label, style: AppText.label.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
