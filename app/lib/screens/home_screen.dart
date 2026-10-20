import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import '../widgets/small_widgets.dart';
import 'category_screen.dart';

/// 홈(서랍 탭): 큰 제목 · 잊은 관심사 카드 · 카테고리 알약.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _seenRevision = -1;
  CategorySummary? _summary;
  Interest? _interest;

  // store가 알리면(예: 카테고리 수정) 이 메서드가 다시 불려 데이터를 새로 읽는다.
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
    final summary = await store.repository.summary();
    final interests = await store.repository.interests();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _interest = interests.isEmpty ? null : interests.first;
    });
  }

  void _open(BuildContext context, CategoryScreen screen) {
    Navigator.of(context).push(appRoute(context, (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    final store = RemineScope.of(context);
    final largest = summary.largest;
    final interest = _interest;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('remine.', style: AppText.brand()),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.ink, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    formatWeekdayDate(store.now()),
                    style: AppText.numBadge(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s24),
          const HighlighterText(before: '잊고 있던 거,\n다시 ', highlight: '캐냈어요'),
          const SizedBox(height: AppSpacing.s24),
          if (interest != null) ...[
            InterestCard(
              interest: interest,
              onTap: () => _open(
                context,
                CategoryScreen(
                  category: interest.category,
                  initialTag: interest.tag,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s32),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('내 캡처 서랍', style: AppText.sectionTitle),
              Text(
                '${summary.total} shots',
                style: AppText.numBadge(color: AppColors.inkSub)
                    .copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final item in summary.sortedForHome)
                CategoryPill(
                  item: item,
                  filled: item.category == largest,
                  onTap: () =>
                      _open(context, CategoryScreen(category: item.category)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
