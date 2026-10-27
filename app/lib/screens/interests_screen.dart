import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import '../widgets/interest_brain_map.dart';
import 'tag_screen.dart';

/// 관심사 탭: 반복해서 캡처한 관심사 카드 목록. 없으면 빈 상태 안내.
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
    return AnimatedSwitcher(
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
          Text('잊은 관심사', style: AppText.title),
          const SizedBox(height: AppSpacing.s24),
          if (interests.isEmpty)
            const _EmptyInterests()
          else
            for (final interest in interests) ...[
              InterestCard(
                interest: interest,
                onTap: () => Navigator.of(context).push(
                  appRoute(
                    context,
                    (_) => TagScreen(
                      tag: interest.tag,
                      windowDays: interest.spanDays,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
        ],
      ),
    );
  }
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
