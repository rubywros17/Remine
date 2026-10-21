import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/remine_store.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import '../widgets/home_widgets.dart';
import '../widgets/small_widgets.dart';
import '../widgets/sync_banner.dart';
import 'category_screen.dart';
import 'excluded_screen.dart';
import 'settings_screen.dart';
import 'debug_ocr_screen.dart';

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
  int _excludedCount = 0;

  // store가 알리면(예: 카테고리 수정) 이 메서드가 다시 불려 데이터를 새로 읽는다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = RemineScope.of(context);
    if (_seenRevision != store.revision) {
      _seenRevision = store.revision;
      _load(store, DeviceScope.maybeOf(context));
    }
  }

  Future<void> _load(RemineStore store, DeviceServices? device) async {
    final summary = await store.repository.summary();
    final interests = await store.repository.interests();
    final excluded = device == null
        ? 0
        : (await device.capture.verdicts.deviceOnly(hidden: true)).length;
    if (!mounted) return;
    setState(() {
      _excludedCount = excluded;
      _summary = summary;
      _interest = interests.isEmpty ? null : interests.first;
    });
  }

  void _openDebugOcr(BuildContext context) {
    final services = DeviceScope.maybeOf(context);
    if (!kDebugMode || services == null) return;
    Navigator.of(context)
        .push(appRoute(context, (_) => DebugOcrScreen(services: services)));
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(appRoute(context, (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    final store = RemineScope.of(context);
    final largest = summary.largest;
    final interest = _interest;
    final device = DeviceScope.maybeOf(context);

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
          // 디버그 빌드 + 기기 모드에서만: 워드마크를 길게 누르면 OCR 측정 화면. 릴리스에서는 이 분기가 통째로 빠진다.
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: kDebugMode ? () => _openDebugOcr(context) : null,
                  child: BrandHeader(pillText: formatWeekdayDate(store.now())),
                ),
              ),
              if (device != null)
                RoundIconButton(
                  icon: LucideIcons.settings,
                  label: '설정',
                  onTap: () =>
                      _open(context, SettingsScreen(settings: device.settings)),
                ),
            ],
          ),
          if (device?.remote != null) SyncBanner(remote: device!.remote!),
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
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // 두 글자 모두 폭이 모자라면 줄어들고(말줄임) 넘치지 않는다.
              Flexible(
                child: Text(
                  '내 캡처 서랍',
                  style: AppText.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Flexible(
                child: Text(
                  '${summary.total} shots',
                  style: AppText.numBadge(color: AppColors.inkSub)
                      .copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
              if (device != null)
                ExcludedPill(
                  count: _excludedCount,
                  onTap: () => _open(
                    context,
                    ExcludedScreen(
                      verdicts: device.capture.verdicts,
                      reader: device.reader,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
