import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/older_progress.dart';
import '../data/remine_store.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import '../widgets/interest_brain_map.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/reveal_section.dart';
import '../widgets/small_widgets.dart';
import 'older_range_screen.dart';
import 'older_shots_screen.dart';
import 'older_texts.dart';
import 'tag_screen.dart';

/// 관심사 탭: 반복해서 캡처한 관심사 카드 목록을 "잊고 있었던 관심사"(레몬)와 "요즘 모으는 중"(셀라돈) 두 섹션으로.
/// 잊고 있었던 관심사는 처음 2개, 요즘 모으는 중은 3개만 보이고 [더 보기]로 펼치고 [접기]로 접는다.
/// 오른쪽 위 검색으로 이미 불러온 목록을 태그로 거른다(서버 호출 없음). 관심사가 아예 없으면 빈 상태 안내.
/// 다른 탭에 갔다 오면 펼침·검색은 처음 상태로, 태그 화면에 갔다 오면 그대로다.
///
/// 홈과 같은 방식으로 store가 바뀌면(카테고리 수정·휴지통) 다시 읽는다.
/// 탭에 들어올 때마다([active]가 켜질 때) 먼저 머릿속 캡처 지도([InterestBrainMap])를 보여 주고,
/// [목록 보기]나 화면을 누르면 목록으로 넘어간다. 관심사가 없으면 바로 빈 상태다.
/// (태그 화면에 갔다가 돌아오면 탭은 계속 보이던 중이라 목록 그대로다.)
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key, this.active = true});

  /// 이 탭이 지금 보이는지. 탭 화면들은 앱이 켜질 때 한꺼번에 만들어져서(IndexedStack) 따로 알려 준다.
  final bool active;

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  int _seenRevision = -1;

  /// 처음에 보이는 카드 수. [더 보기]를 누르면 그 섹션 전부.
  static const _forgottenPreview = 2;
  static const _recentPreview = 3;
  bool _forgottenOpen = false;
  bool _recentOpen = false;

  /// 접으면 그 섹션 머리가 보이게 스크롤한다.
  final _forgottenHeader = GlobalKey();
  final _recentHeader = GlobalKey();

  /// 검색창이 열려 있는지와 입력값.
  bool _searching = false;
  final _query = TextEditingController();
  final _searchFocus = FocusNode();

  /// 목록 스크롤. "맨 아래로 / 맨 위로" 버튼이 보일지·방향을 정한다.
  final _scroll = ScrollController();

  /// 마지막으로 그린 (화면 절반 이상 내림, 맨 아래 근처). 바뀔 때만 다시 그린다.
  (bool, bool) _jump = (false, false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchFocus.addListener(() => setState(() {}));
  }

  (bool, bool) get _jumpState {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return (false, false);
    }
    final p = _scroll.position;
    final half = p.viewportDimension / 2;
    return (p.pixels >= half, p.maxScrollExtent - p.pixels < half);
  }

  void _onScroll() {
    final now = _jumpState;
    if (now != _jump) setState(() => _jump = now);
  }

  /// 아래 모양이면 맨 아래로, 위 모양이면 맨 위로. 애니메이션 줄이기면 바로 이동.
  Future<void> _jumpTo({required bool top}) async {
    final p = _scroll.position;
    if (AppMotion.reduced(context)) {
      _scroll.jumpTo(top ? 0 : p.maxScrollExtent);
      // 아래쪽 카드가 처음 그려지며 목록 길이가 늘었으면 다음 프레임에 끝까지 마저 간다.
      if (!top) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && p.pixels < p.maxScrollExtent) {
            _scroll.jumpTo(p.maxScrollExtent);
          }
        });
      }
      return;
    }
    // 아주 멀면 끝에서 화면 몇 개 앞까지 바로 간 뒤 남은 구간만 부드럽게(긴 목록에서 버벅이지 않게).
    final screen = p.viewportDimension;
    var distance = ((top ? 0 : p.maxScrollExtent) - p.pixels).abs();
    if (distance >= screen * AppScrollJump.longJumpScreens) {
      final tail = screen * AppScrollJump.tailScreens;
      _scroll.jumpTo(top ? tail : p.maxScrollExtent - tail);
      distance = tail;
    }
    await _scroll.animateTo(
      top ? 0 : p.maxScrollExtent,
      duration: AppScrollJump.travel(distance, screen),
      curve: AppScrollJump.travelCurve,
    );
    // 아래쪽 카드가 처음 그려지며 목록 길이가 늘었으면 끝까지 마저 부드럽게 간다.
    if (!top && mounted && p.pixels < p.maxScrollExtent) {
      await _scroll.animateTo(
        p.maxScrollExtent,
        duration: AppScrollJump.settle,
        curve: AppMotion.standard,
      );
    }
  }

  /// 이번에 탭에 들어와서 아직 목록으로 넘어가지 않았는지.
  bool _showMap = true;

  /// 들어올 때마다 늘려서 지도가 처음부터 다시 그려지게 한다(위젯 key).
  int _entry = 0;

  /// null = 아직 불러오는 중.
  List<Interest>? _interests;
  int _loadSeq = 0;

  /// 예전 스크린샷 현황(기기 모드만). 목록 맨 아래 점선 칸("더 오래된 관심사도…")에 쓴다.
  OlderOverview? _older;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RemineScope.of(context);
    if (_seenRevision != store.revision) {
      _seenRevision = store.revision;
      _load(store);
      _loadOlder(); // 동기화가 끝나 목록이 바뀔 때 남은 장수도 다시
    }
  }

  Future<void> _loadOlder() async {
    final device = DeviceScope.maybeOf(context);
    if (device == null) return;
    final o = await loadOlderOverview(device.reader, device.settings);
    if (mounted) setState(() => _older = o);
  }

  /// 범위를 골랐으면 예전 스크린샷 화면, 아니면 범위 고르기(설정 모드).
  Future<void> _openOlder() async {
    final device = DeviceScope.maybeOf(context);
    if (device == null) return;
    await Navigator.of(context).push<void>(
      appRoute(
        context,
        (_) => _older?.chosen == true
            ? OlderShotsScreen(
                settings: device.settings,
                reader: device.reader,
                remote: device.remote,
              )
            : OlderRangeScreen(
                settings: device.settings,
                reader: device.reader,
                fromSettings: true,
              ),
      ),
    );
    _loadOlder();
  }

  Future<void> _load(RemineStore store) async {
    final seq = ++_loadSeq;
    final interests = await store.repository.interests();
    if (!mounted || seq != _loadSeq) return;
    setState(() => _interests = interests);
  }

  @override
  void didUpdateWidget(InterestsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _showMap = true;
      _entry++;
      // 다른 탭에 갔다 오면 처음 상태로
      _forgottenOpen = false;
      _recentOpen = false;
      _closeSearch();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searching = false;
    _query.clear();
  }

  /// 대소문자·띄어쓰기·'#'를 무시한 비교 키.
  static String _key(String s) =>
      s.replaceAll('#', '').replaceAll(RegExp(r'\s+'), '').toLowerCase();

  @override
  Widget build(BuildContext context) {
    final interests = _interests;
    if (interests == null) return const SizedBox.shrink();
    final map = _showMap && widget.active && interests.isNotEmpty;
    // 탭에 들어올 때마다(_entry) 새 AnimatedSwitcher: 이전 목록과 크로스페이드하지 않아 첫 프레임부터 지도만 보인다.
    // 지도 → 목록은 같은 AnimatedSwitcher 안이라 크로스페이드한다.
    return AnimatedSwitcher(
      key: ValueKey('switcher-$_entry'),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppBrain.crossfade,
      child: map
          ? InterestBrainMap(
              key: ValueKey('brain-$_entry'),
              interests: interests,
              onList: () => setState(() => _showMap = false),
            )
          : KeyedSubtree(key: const ValueKey('list'), child: _list(interests)),
    );
  }

  Widget _list(List<Interest> interests) {
    final query = _key(_query.text);
    final filtering = _searching && query.isNotEmpty;
    final matched = filtering
        ? interests.where((i) => _key(i.tag).contains(query)).toList()
        : interests;
    final forgotten = matched.where((i) => i.forgotten).toList();
    final recent = matched.where((i) => !i.forgotten).toList();
    // 검색 중에는 더 보기 없이 전부
    final showForgotten = filtering || _forgottenOpen
        ? forgotten
        : forgotten.take(_forgottenPreview).toList();
    final showRecent = filtering || _recentOpen
        ? recent
        : recent.take(_recentPreview).toList();
    // 펼쳐진 카드가 많고 화면 절반 이상 내렸을 때만. 키보드(검색 입력 중)가 올라와 있으면 숨긴다.
    final cards = showForgotten.length + showRecent.length;
    final (scrolled, nearBottom) = _jumpState;
    final keyboard =
        _searchFocus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0;
    final showJump = cards > AppScrollJump.minCards && scrolled && !keyboard;
    // 빈 상태도 ListView 안에 둬서 작은 화면·큰 글꼴에서 넘치지 않고 스크롤된다.
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          ListView(
            controller: _scroll,
            // 아래 여백: 마지막 카드가 떠 있는 버튼에 가리지 않게
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.s16,
              AppSpacing.screenPadding,
              AppSpacing.s24 + AppScrollJump.size + AppScrollJump.gap,
            ),
            children: [
              _searching ? _searchBar() : _titleBar(interests.isNotEmpty),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '여러 번 캡처한 것들을 모았어요',
                style: AppText.caption.copyWith(color: AppColors.inkSub),
              ),
              const SizedBox(height: AppSpacing.s20),
              if (interests.isEmpty)
                const _EmptyInterests()
              else if (filtering && matched.isEmpty)
                _NoMatch(query: _query.text.trim())
              else ...[
                // 검색 중에는 맞는 것이 없는 섹션을 숨긴다(점선 안내도 검색 아닐 때만).
                if (!filtering || forgotten.isNotEmpty)
                  _SectionHeader(
                    key: _forgottenHeader,
                    title: '잊고 있었던 관심사',
                    count: forgotten.length,
                    dot: AppColors.lemon,
                  ),
                if (forgotten.isEmpty && !filtering) const _NoForgotten(),
                if (filtering || forgotten.length <= _forgottenPreview)
                  for (final interest in forgotten) _card(interest)
                else ...[
                  for (final interest in forgotten.take(_forgottenPreview))
                    _card(interest),
                  RevealSection(
                    key: const ValueKey('reveal-forgotten'),
                    open: _forgottenOpen,
                    cards: [
                      for (final interest in forgotten.skip(_forgottenPreview))
                        _card(interest),
                    ],
                    more: _HighlightButton(
                      text:
                          '잊고 있었던 관심사 ${forgotten.length - _forgottenPreview}개 더 보기 ↓',
                      onTap: () => setState(() => _forgottenOpen = true),
                    ),
                    collapse: (onTap) => _HighlightButton(
                      text: '접기 ↑',
                      label: '잊고 있었던 관심사 접기',
                      onTap: onTap,
                    ),
                    onCollapse: () => setState(() => _forgottenOpen = false),
                    header: _forgottenHeader,
                  ),
                ],
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  _SectionHeader(
                    key: _recentHeader,
                    title: '요즘 모으는 중',
                    count: recent.length,
                    dot: AppColors.celadon,
                  ),
                  if (filtering || recent.length <= _recentPreview)
                    for (final interest in recent) _card(interest)
                  else ...[
                    for (final interest in recent.take(_recentPreview))
                      _card(interest),
                    RevealSection(
                      key: const ValueKey('reveal-recent'),
                      open: _recentOpen,
                      cards: [
                        for (final interest in recent.skip(_recentPreview))
                          _card(interest),
                      ],
                      more: _HighlightButton(
                        color: AppColors.celadon,
                        text:
                            '요즘 모으는 중 ${recent.length - _recentPreview}개 더 보기 ↓',
                        onTap: () => setState(() => _recentOpen = true),
                      ),
                      collapse: (onTap) => _HighlightButton(
                        color: AppColors.celadon,
                        text: '접기 ↑',
                        label: '요즘 모으는 중 접기',
                        onTap: onTap,
                      ),
                      onCollapse: () => setState(() => _recentOpen = false),
                      header: _recentHeader,
                    ),
                  ],
                ],
                // 목록 끝: 아직 안 본 예전 스크린샷이 있으면(검색 중 아님) 범위를 넓히는 입구.
                if (!filtering && (_older?.unseen ?? 0) > 0) ...[
                  const SizedBox(height: AppSpacing.s8),
                  _OlderMore(count: _older!.unseen, onTap: _openOlder),
                ],
              ],
            ],
          ),
          Positioned(
            right: AppScrollJump.gap,
            bottom: AppScrollJump.gap,
            child: ScrollJumpButton(
              visible: showJump,
              up: nearBottom,
              onTap: () => _jumpTo(top: nearBottom),
            ),
          ),
        ],
      ),
    );
  }

  /// 제목 줄: "관심사" + 오른쪽 검색 아이콘(관심사가 있을 때만).
  Widget _titleBar(bool canSearch) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text('관심사', style: AppText.title),
        ),
      ),
      if (canSearch)
        IconButton(
          tooltip: '관심사 검색',
          icon: const Icon(LucideIcons.search, color: AppColors.ink),
          onPressed: () => setState(() => _searching = true),
        ),
    ],
  );

  /// 검색 중 제목 줄: 입력창(키보드 바로 올라옴) + 닫기.
  Widget _searchBar() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _query,
          focusNode: _searchFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: AppText.body,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '태그로 찾기',
            hintStyle: AppText.body.copyWith(color: AppColors.inkSub),
            prefixIcon: const Icon(LucideIcons.search, color: AppColors.inkSub),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              borderSide: const BorderSide(color: AppColors.ink),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: '검색 닫기',
        icon: const Icon(LucideIcons.x, color: AppColors.ink),
        onPressed: () => setState(_closeSearch),
      ),
    ],
  );

  Widget _card(Interest interest) => Padding(
    key: ValueKey('interest-${interest.tag}'),
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: InterestCard(
      interest: interest,
      onTap: () => Navigator.of(context).push(
        fadeThroughRoute(
          context,
          (_) => TagScreen(tag: interest.tag, forgotten: interest.forgotten),
          // 콜라주 Hero가 돌아올 때 빈 바탕 위를 날지 않게.
          heroes: false,
        ),
      ),
    ),
  );
}

/// 섹션 머리: 색 점 + 굵은 제목 + 개수. 화면 리더는 "잊고 있었던 관심사 3개"로 한 번에 읽는다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.dot,
  });

  final String title;
  final int count;
  final Color dot;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: Semantics(
      header: true,
      label: '$title $count개',
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: AppCategoryColors.dotSize,
            height: AppCategoryColors.dotSize,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              border: Border.all(color: AppCategoryColors.dotOutline),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.cardTitle,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text('$count', style: AppText.numBadge(color: AppColors.inkSub)),
        ],
      ),
    ),
  );
}

/// "… N개 더 보기 ↓"·"접기 ↑": 검정 굵은 글씨 + 아래쪽 절반 형광펜(태그 화면 제목과 같은 표현, 색은 섹션 색).
class _HighlightButton extends StatelessWidget {
  const _HighlightButton({
    required this.text,
    required this.onTap,
    this.label,
    this.color = AppColors.lemon,
  });

  /// 형광펜 색: 잊고 있었던 관심사는 레몬, 요즘 모으는 중은 셀라돈(섹션 점 색과 같게).
  final Color color;

  final String text;
  final VoidCallback onTap;

  /// 화면 리더 문장. 없으면 [text]에서 화살표만 뺀다.
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: Center(
      child: PressableScale(
        onTap: onTap,
        label: label ?? text.replaceAll(RegExp(r' [↓↑]$'), ''),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            heightFactor: 1,
            child: DecoratedBox(
              decoration: highlighterDecoration(color: color),
              child: Text(
                text,
                style: AppText.body.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// "맨 아래로 / 맨 위로" 떠 있는 버튼: 지름 48 검정 원 + 흰 겹화살표(정가운데), 약한 그림자.
/// 숨을 때도 자리에 남아 페이드 + 살짝 작아지고, 누를 수 없고 화면 리더도 읽지 않는다.
class ScrollJumpButton extends StatelessWidget {
  const ScrollJumpButton({
    super.key,
    required this.visible,
    required this.up,
    required this.onTap,
  });

  final bool visible;

  /// true면 위 화살표("맨 위로"), false면 아래 화살표("맨 아래로").
  final bool up;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = AppMotion.reduced(context) ? Duration.zero : AppScrollJump.appear;
    final icon = Icon(
      up ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down,
      key: ValueKey(up),
      size: AppScrollJump.iconSize,
      color: AppColors.white,
    );
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: d,
          curve: AppMotion.standard,
          child: AnimatedScale(
            scale: visible ? 1 : AppScrollJump.hiddenScale,
            duration: d,
            curve: AppMotion.standard,
            child: Semantics(
              button: true,
              label: up ? '맨 위로' : '맨 아래로',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  key: const ValueKey('scroll-jump'),
                  width: AppScrollJump.size,
                  height: AppScrollJump.size,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                    boxShadow: [AppScrollJump.shadow],
                  ),
                  // 아래 ↔ 위가 바뀔 때 크로스페이드(회전보다 화살표 모양이 덜 흔들린다).
                  // 애니메이션 줄이기면 그냥 바꾼다.
                  child: Center(
                    child: AppMotion.reduced(context)
                        ? icon
                        : AnimatedSwitcher(
                            duration: AppScrollJump.iconSwap,
                            child: icon,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 검색 결과가 없을 때.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
    child: Text(
      "'$query'와 맞는 관심사가 없어요",
      style: AppText.body,
      textAlign: TextAlign.center,
    ),
  );
}

/// 목록 맨 아래 점선 칸: 예전 스크린샷까지 보면 더 오래된 관심사를 찾을 수 있다.
class _OlderMore extends StatelessWidget {
  const _OlderMore({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: CustomPaint(
      key: const ValueKey('older-more'),
      painter: const DashedBorderPainter(radius: AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          children: [
            Text(
              OlderTexts.moreTitle,
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              OlderTexts.moreBody(count),
              style: AppText.caption.copyWith(color: AppColors.inkSub),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s12),
            PressableScale(
              onTap: onTap,
              label: OlderTexts.moreButton,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16,
                    vertical: 10,
                  ),
                  child: Text(
                    OlderTexts.moreButton,
                    textAlign: TextAlign.center,
                    style: AppText.label.copyWith(color: AppColors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 잊고 있었던 관심사가 아직 없을 때의 점선 칸.
class _NoForgotten extends StatelessWidget {
  const _NoForgotten();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: CustomPaint(
      painter: const DashedBorderPainter(radius: AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          children: [
            Text(
              '아직 잊고 있었던 관심사가 없어요',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              '한 달 넘게 안 찾은 관심사가 생기면 여기서 다시 꺼내 드릴게요',
              style: AppText.caption.copyWith(color: AppColors.inkSub),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyInterests extends StatelessWidget {
  const _EmptyInterests();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        children: [
          const Icon(LucideIcons.sparkles, size: 32, color: AppColors.inkSub),
          const SizedBox(height: AppSpacing.s12),
          Text(
            '아직 반복해서 캡처한 게 없어요',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '같은 걸 여러 번 캡처하면 여기 모여요',
            style: AppText.caption.copyWith(color: AppColors.inkSub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
