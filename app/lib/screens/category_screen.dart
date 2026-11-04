import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/category.dart';
import '../models/screenshot_item.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/capture_grid.dart';
import '../widgets/small_widgets.dart';
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

  /// 불러오기 요청 번호. 응답이 순서 없이 도착해도(동기화 배치·카테고리 수정이 겹칠 때) 가장 마지막 요청의 결과만 화면에 쓴다.
  int _loadSeq = 0;

  // 상세를 보고 돌아왔을 때 마지막으로 본 타일이 화면에 보이게 하는 데 쓴다.
  final Map<int, GlobalKey> _tileKeys = {};
  List<int> _openSnapshot = const []; // 상세를 열 때의 목록(id 순서)
  int? _lastViewing;

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
    final repo = store.repository;
    final summary = await repo.summary();
    // 칩에 쓸 태그는 이 카테고리 전체에서, 그리드는 선택된 태그로 거른 결과.
    final all = await repo.list(category: widget.category, size: 100);
    final filtered = await repo.list(
      category: widget.category,
      tag: _tag,
      size: 100,
    );
    if (!mounted || seq != _loadSeq) return; // 더 새 요청이 있으면 이 옛 응답은 버린다

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
    // 목록이 바뀐 뒤(카테고리 수정·휴지통)에도 마지막으로 본 항목(또는 이웃)이 보이게 다시 맞춘다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _lastViewing;
      if (mounted && id != null) _reveal(id);
    });
  }

  void _openDetail(int index) {
    _openSnapshot = _items.map((s) => s.id).toList();
    _lastViewing = _items[index].id;
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => DetailScreen(
          items: List.of(_items),
          initialIndex: index,
          onViewing: (id) {
            _lastViewing = id;
            _reveal(id);
          },
        ),
      ),
    );
  }

  /// [id] 항목의 타일이 보이게 즉시 스크롤한다. 그 항목이 이 그리드에서 빠졌으면(카테고리 수정·휴지통)
  /// 상세를 열 때의 순서에서 가장 가까운 남은 항목으로 대신한다. Hero가 돌아올 자리가 화면 안에 있게 하려는 것.
  void _reveal(int id) {
    final order = _openSnapshot;
    final start = order.indexOf(id);
    if (start < 0) return;
    for (var d = 0; d < order.length; d++) {
      for (final i in {start + d, start - d}) {
        if (i < 0 || i >= order.length) continue;
        final ctx = _tileKeys[order[i]]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: Duration.zero,
          );
          return;
        }
      }
    }
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
                    // 바탕 위 큰 숫자는 차콜(darkGray, 대비 8.72:1).
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$_count',
                        style: AppText.numHero(color: AppColors.darkGray),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              _TagRow(
                category: widget.category,
                tags: _allTags,
                selected: _tag,
                onSelect: _selectTag,
              ),
              const SizedBox(height: AppSpacing.s20),
              if (_loaded)
                CaptureGrid(
                  items: _items,
                  keyFor: (id) => _tileKeys.putIfAbsent(id, GlobalKey.new),
                  onOpen: _openDetail,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.category,
    required this.tags,
    required this.selected,
    required this.onSelect,
  });

  final Category category;
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
          // 선택됨: 카테고리 색 채움. 밝은 색(기타·정보)에서도 보이게 색 말고도 굵은 글자 + 차콜 2px 테두리.
          child: on
              ? AppChip(
                  label: label,
                  background: AppCategoryColors.of(category),
                  borderColor: AppCategoryColors.pillBorder,
                  borderWidth: 2,
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                )
              : AppChip.outlined(label: label),
        ),
      ),
    );
  }
}
