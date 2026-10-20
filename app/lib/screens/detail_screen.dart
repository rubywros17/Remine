import 'package:flutter/material.dart';
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

/// 스크린샷 상세: 셀라돈 배경, 기울어진 이미지 카드, 하단 카드(출처·카테고리 칩·요약·태그·"더 보기").
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});

  final ScreenshotItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late ScreenshotItem _item = widget.item;
  int _sameInterestCount = 0;

  String? get _mainTag => _item.tags.isEmpty ? null : _item.tags.first;

  bool _requested = false;

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
    setState(
      () => _item = _item.copyWith(
        category: result.category,
        categorySource: result.categorySource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = _mainTag;
    return Scaffold(
      backgroundColor: AppColors.celadon,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                AppSpacing.s8,
                AppSpacing.screenPadding,
                0,
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: BackButtonCircle(background: AppColors.white),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                child: _ImageCard(item: _item, tag: tag),
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
  }
}

/// 기울어진 흰 이미지 카드(플레이스홀더) + #태그 스티커. 카드는 Hero로 그리드 썸네일에서 이어진다.
class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.item, required this.tag});

  final ScreenshotItem item;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final (_, block) = ThumbPlaceholder.colorsFor(item.id);
    return ExcludeSemantics(
      // 사용할 수 있는 영역을 세로·가로 모두 넘지 않게 비율 0.62로 맞춘다.
      child: LayoutBuilder(
        builder: (context, box) {
          var width = box.maxHeight * 0.62;
          if (width > box.maxWidth * 0.68) width = box.maxWidth * 0.68;
          return Center(
            child: SizedBox(
              width: width,
              height: width / 0.62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Hero(
                      tag: 'screenshot-${item.id}',
                      child: Transform.rotate(
                        angle: decorAngle(item.id, max: 0.07),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: block.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.tile,
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s12),
                                _bar(double.infinity, AppColors.chip),
                                const SizedBox(height: AppSpacing.s8),
                                _bar(120, AppColors.chip),
                                const SizedBox(height: AppSpacing.s8),
                                _bar(64, AppColors.border),
                                const Spacer(),
                                _bar(
                                  double.infinity,
                                  AppColors.darkGray,
                                  height: 34,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (tag != null)
                    Positioned(
                      top: -10,
                      right: -14,
                      child: Sticker(label: '#$tag', angle: 0.1),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bar(double width, Color color, {double height = 10}) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.pill),
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
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.card + 4),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        source,
                        style: AppText.caption.copyWith(fontSize: 13),
                      ),
                    ),
                    // 카테고리 칩: 누르면 수정 시트
                    PressableScale(
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
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.lemon,
                          borderRadius: BorderRadius.circular(AppRadii.tile),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '같은 관심사 캡처 $sameInterestCount장 더 보기',
                                  style: AppText.label.copyWith(fontSize: 15),
                                ),
                              ),
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
      ),
    );
  }
}
