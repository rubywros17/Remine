import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/category.dart';
import '../models/screenshot_item.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/small_widgets.dart';
import '../widgets/thumb_placeholder.dart';
import 'detail_screen.dart';

/// 카테고리 상세: 큰 제목 + 거대한 개수, 태그 칩 필터, 높이가 다른 2열 엇갈림 그리드.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category, this.initialTag});

  final Category category;

  /// 처음부터 선택해 둘 태그(관심사 카드에서 들어올 때).
  final String? initialTag;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  int _seenRevision = -1;
  late String? _tag = widget.initialTag;
  int _count = 0;
  List<String> _allTags = const [];
  List<ScreenshotItem> _items = const [];
  bool _loaded = false;

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
    final repo = store.repository;
    final summary = await repo.summary();
    // 칩에 쓸 태그는 이 카테고리 전체에서, 그리드는 선택된 태그로 거른 결과.
    final all = await repo.list(category: widget.category, size: 100);
    final filtered = await repo.list(
      category: widget.category,
      tag: _tag,
      size: 100,
    );
    if (!mounted) return;

    final counts = <String, int>{};
    for (final s in all.items) {
      for (final t in s.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final tags = counts.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    setState(() {
      _count = summary.of(widget.category).count;
      _allTags = tags.map((e) => e.key).toList();
      _items = filtered.items;
      _loaded = true;
    });
  }

  void _selectTag(String? tag) {
    _tag = _tag == tag ? null : tag; // 같은 칩을 다시 누르면 해제
    _load(RemineScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.s8,
            AppSpacing.screenPadding,
            AppSpacing.s32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: BackButtonCircle(),
              ),
              const SizedBox(height: AppSpacing.s8),
              // 제목과 개수. 개수는 화면 리더가 "쇼핑 42장"으로 한 번에 읽게 묶는다.
              Semantics(
                label: '${widget.category.label} $_count장',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(widget.category.label, style: AppText.title),
                    ),
                    // 바탕 위 큰 숫자는 딥 셀라돈(대비 3.70:1). 일반 셀라돈은 1.90:1이라 쓰지 않는다.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$_count',
                        style: AppText.numHero(color: AppColors.celadonDeep),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              _TagRow(tags: _allTags, selected: _tag, onSelect: _selectTag),
              const SizedBox(height: AppSpacing.s20),
              if (_loaded) _StaggeredGrid(items: _items),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tags,
    required this.selected,
    required this.onSelect,
  });

  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(label: '전체', on: selected == null, onTap: () => onSelect(null)),
          for (final tag in tags) ...[
            const SizedBox(width: AppSpacing.s8),
            _chip(
              label: '#$tag',
              on: selected == tag,
              onTap: () => onSelect(tag),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      label: '$label${on ? ', 선택됨' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          child: on
              ? AppChip.selected(label: label)
              : AppChip.outlined(label: label),
        ),
      ),
    );
  }
}

/// 두 열로 나누고 높이를 달리해 엇갈리게 쌓는다. (한 화면에 담기는 개수가 적어 단순 Column 두 개로 만들었다.
/// 실제 서버 연동에서 수백 장이 되면 지연 로딩 그리드로 바꾼다.)
class _StaggeredGrid extends StatelessWidget {
  const _StaggeredGrid({required this.items});

  final List<ScreenshotItem> items;

  static const _heights = [230.0, 170.0, 200.0, 250.0, 160.0];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s40),
        child: Center(child: Text('아직 여기엔 아무것도 없어', style: AppText.body)),
      );
    }
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final tile = Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
        child: _Tile(
          item: items[i],
          height: _heights[(items[i].id + i) % _heights.length],
        ),
      );
      (i.isEven ? left : right).add(tile);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: AppSpacing.s12),
        // 오른쪽 열을 아래로 밀어 엇갈리게
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Column(children: right),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.height});

  final ScreenshotItem item;
  final double height;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () =>
          Navigator.of(context)
              .push(appRoute(context, (_) => DetailScreen(item: item))),
      label:
          '${item.summary ?? item.category.label}, ${formatMonthDay(item.takenAt)}',
      child: SizedBox(
        height: height,
        child: Hero(
          tag: 'screenshot-${item.id}',
          child: ThumbPlaceholder(
            seed: item.id,
            child: Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    formatMonthDay(item.takenAt),
                    style: AppText.numBadge(),
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
