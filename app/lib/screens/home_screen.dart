import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/remine_store.dart';
import '../models/category_summary.dart';
import '../models/interest.dart';
import '../widgets/grow_column.dart';
import '../widgets/home_widgets.dart';
import '../widgets/small_widgets.dart';
import '../widgets/sync_banner.dart';
import 'analysis_preview_screen.dart';
import 'category_screen.dart';
import 'tag_screen.dart';
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

  /// 불러오기 요청 번호. 늦게 도착한 옛 응답이 새 결과를 덮어쓰지 않게 한다.
  int _loadSeq = 0;

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
    final seq = ++_loadSeq;
    final summary = await store.repository.summary();
    final interests = await store.repository.interests();
    final excluded = device == null
        ? 0
        : (await device.capture.verdicts.deviceOnly(hidden: true)).length;
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _excludedCount = excluded;
      _summary = summary;
      _interest = interests.isEmpty ? null : interests.first;
    });
  }

  void _openDebug(BuildContext context) {
    if (!kDebugMode) return;
    final services = DeviceScope.maybeOf(context);
    Navigator.of(context).push(
      appRoute(
        context,
        // 가짜 데이터 모드(크롬)에는 기기 서비스가 없어 디버그 화면을 못 띄우므로 미리보기로 바로 간다.
        (_) => services == null
            ? const AnalysisPreviewScreen()
            : DebugOcrScreen(services: services),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(appRoute(context, (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    final store = RemineScope.of(context);
    final sorted = summary.sortedForHome;
    final interest = _interest;
    final device = DeviceScope.maybeOf(context);

    // 제목 ↔ 관심사 카드와 관심사 카드 ↔ 서랍 제목이 "보이는 글자 끝" 기준으로 같게:
    // 제목 글자 아래 끝은 글자 박스보다 위에, 서랍 제목 글자 위 끝은 박스보다 아래에 있어서 그 차이만큼 보정한다.
    final textScaler = MediaQuery.textScalerOf(context);
    final cardToDrawer =
        AppSpacing.s24 +
        textScaler.scale(AppText.display.fontSize!) * AppHome.titleInkBottom -
        textScaler.scale(AppText.sectionTitle.fontSize!) *
            AppHome.drawerTitleInkTop;

    // 화면이 남으면 두 간격이 똑같이 늘어(값은 AppHome) 카드와 서랍 묶음이 같이 내려가고,
    // 나머지는 알약 아래에 남는다. 모자라면 평소처럼 스크롤된다.
    // [Flutter 메모] LayoutBuilder로 화면(스크롤 영역) 높이를 받아 GrowColumn의 최소 높이로 준다.
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.s16,
            AppSpacing.screenPadding,
            0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, viewport.maxHeight - AppSpacing.s16),
            ),
            child: GrowColumn(
              children: [
                // 디버그 빌드에서만: 워드마크를 길게 누르면 디버그 화면(가짜 데이터 모드는 첫 분석 미리보기). 릴리스에서는 이 분기가 통째로 빠진다.
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onLongPress: kDebugMode
                            ? () => _openDebug(context)
                            : null,
                        child: BrandHeader(
                          pillText: formatWeekdayDate(store.now()),
                        ),
                      ),
                    ),
                    if (device != null)
                      RoundIconButton(
                        icon: LucideIcons.settings,
                        label: '설정',
                        onTap: () => _open(
                          context,
                          SettingsScreen(
                            settings: device.settings,
                            remote: device.remote,
                            trash: device.trash,
                          ),
                        ),
                      ),
                  ],
                ),
                if (device?.remote != null) SyncBanner(remote: device!.remote!),
                const SizedBox(height: AppSpacing.s24),
                const HighlighterText(
                  before: '잊고 있던 스크린샷,\n다시 ',
                  highlight: '꺼냈어요',
                ),
                if (interest == null)
                  const SizedBox(height: AppSpacing.s24)
                else ...[
                  GrowGap(
                    AppSpacing.s24,
                    share: AppHome.cardGapShare,
                    maxExtra: AppHome.cardGapMaxExtra,
                  ),
                  InterestCard(
                    interest: interest,
                    onTap: () => _open(
                      context,
                      TagScreen(
                        tag: interest.tag,
                        windowDays: interest.spanDays,
                      ),
                    ),
                  ),
                  GrowGap(
                    cardToDrawer,
                    share: AppHome.cardGapShare,
                    maxExtra: AppHome.cardGapMaxExtra,
                  ),
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
                CategoryRatioBar(items: sorted),
                const SizedBox(height: AppSpacing.s16),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final item in sorted)
                      CategoryPill(
                        item: item,
                        onTap: () => _open(
                          context,
                          CategoryScreen(category: item.category),
                        ),
                      ),
                    // 기타 바로 뒤. 카테고리가 아니라 막대에는 들어가지 않는다.
                    if (device != null && _excludedCount > 0)
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
                // 남는 높이의 나머지는 이 아래(탭바 쪽)에 남는다.
                const SizedBox(height: AppHome.pillsToTabMin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
