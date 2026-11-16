import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import '../widgets/interest_brain_map.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/small_widgets.dart';
import 'tag_screen.dart';

/// 관심사 탭: 반복해서 캡처한 관심사 카드 목록을 "잊고 있었던 관심사"(레몬)와 "요즘 모으는 중"(셀라돈) 두 섹션으로.
/// 잊고 있었던 관심사는 처음 2개만 보이고 [더 보기]로 펼친다. 관심사가 아예 없으면 빈 상태 안내.
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

  /// 잊고 있었던 관심사는 처음 [_forgottenPreview]개만, [더 보기]를 누르면 전부.
  static const _forgottenPreview = 2;
  bool _expanded = false;

  /// 이번에 탭에 들어와서 아직 목록으로 넘어가지 않았는지.
  bool _showMap = true;

  /// 들어올 때마다 늘려서 지도가 처음부터 다시 그려지게 한다(위젯 key).
  int _entry = 0;

  /// null = 아직 불러오는 중.
  List<Interest>? _interests;
  int _loadSeq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RemineScope.of(context);
    if (_seenRevision != store.revision) {
      _seenRevision = store.revision;
      _load(store);
    }
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
    }
  }

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
    final forgotten = interests.where((i) => i.forgotten).toList();
    final recent = interests.where((i) => !i.forgotten).toList();
    final shownForgotten = _expanded
        ? forgotten
        : forgotten.take(_forgottenPreview).toList();
    // 빈 상태도 ListView 안에 둬서 작은 화면·큰 글꼴에서 넘치지 않고 스크롤된다.
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.s16,
          AppSpacing.screenPadding,
          AppSpacing.s24,
        ),
        children: [
          Semantics(header: true, child: Text('관심사', style: AppText.title)),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '여러 번 캡처한 것들을 모았어요',
            style: AppText.caption.copyWith(color: AppColors.inkSub),
          ),
          const SizedBox(height: AppSpacing.s20),
          if (interests.isEmpty)
            const _EmptyInterests()
          else ...[
            _SectionHeader(
              title: '잊고 있었던 관심사',
              count: forgotten.length,
              dot: AppColors.lemon,
            ),
            if (forgotten.isEmpty)
              const _NoForgotten()
            else
              for (final interest in shownForgotten) _card(interest),
            if (forgotten.length > shownForgotten.length)
              _MoreButton(
                hidden: forgotten.length - shownForgotten.length,
                onTap: () => setState(() => _expanded = true),
              ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              _SectionHeader(
                title: '요즘 모으는 중',
                count: recent.length,
                dot: AppColors.celadon,
              ),
              for (final interest in recent) _card(interest),
            ],
          ],
        ],
      ),
    );
  }

  Widget _card(Interest interest) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: InterestCard(
      interest: interest,
      compact: !interest.forgotten,
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

/// "잊고 있었던 관심사 N개 더 보기 ↓": 검정 굵은 글씨 + 아래쪽 절반 레몬 형광펜(태그 화면 제목과 같은 표현).
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.hidden, required this.onTap});

  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: Center(
      child: PressableScale(
        onTap: onTap,
        label: '잊고 있었던 관심사 $hidden개 더 보기',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            heightFactor: 1,
            child: DecoratedBox(
              decoration: highlighterDecoration(),
              child: Text(
                '잊고 있었던 관심사 $hidden개 더 보기 ↓',
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
