import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import 'category_screen.dart';

/// 관심사 탭: 반복해서 캡처한 관심사 카드 목록. 없으면 빈 상태 안내.
///
/// 홈과 같은 방식으로 store가 바뀌면(카테고리 수정·휴지통) 다시 읽는다.
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  int _seenRevision = -1;

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
  Widget build(BuildContext context) {
    final interests = _interests;
    if (interests == null) return const SizedBox.shrink();

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
                    (_) => CategoryScreen(
                      category: interest.category,
                      initialTag: interest.tag,
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
