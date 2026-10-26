import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remine_store.dart';
import '../models/screenshot_item.dart';
import '../widgets/capture_grid.dart';
import '../widgets/small_widgets.dart';
import 'detail_screen.dart';

/// 태그 모아보기: 그 태그가 붙은 캡처 전부를 카테고리와 상관없이 최신순으로.
/// 관심사 카드·상세의 "같은 관심사"·관심사 알림에서 들어온다.
///
/// 관심사 카드의 횟수는 최근 [windowDays]일 기준이라, 제목 아래에 "최근 2주 15장 · 전체 40장"을 같이 보여 주고
/// 그리드도 "최근 2주"와 "그 전"으로 나눈다. 상세의 좌우 넘기기는 이 목록(최근 → 그 전) 안에서만 돈다.
class TagScreen extends StatefulWidget {
  const TagScreen({super.key, required this.tag, this.windowDays = 14});

  /// '#' 없는 태그 이름.
  final String tag;

  /// 관심사 집계 기간(서버 `windowDays`). 관심사 카드에서 들어오면 그 값, 아니면 서버 기본값과 같은 14.
  final int windowDays;

  @override
  State<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends State<TagScreen> {
  // ponytail: 최신 100장까지만 받는다(서버 size 상한). 넘으면 "그 전" 구역에 페이지 나누기.
  static const _pageSize = 100;

  int _seenRevision = -1;
  int _loadSeq = 0;
  bool _loaded = false;
  List<ScreenshotItem> _items = const [];
  int _total = 0;
  int _recentCount = 0;

  final Map<int, GlobalKey> _tileKeys = {};
  List<int> _openSnapshot = const [];

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
    final page = await store.repository.list(tag: widget.tag, size: _pageSize);
    if (!mounted || seq != _loadSeq) return;
    // 서버 관심사 집계와 같은 기준: 지금부터 windowDays일 전 이후에 찍은 캡처. 목록이 최신순이라 앞쪽이 최근이다.
    final since = store.now().subtract(Duration(days: widget.windowDays));
    setState(() {
      _items = page.items;
      _total = page.totalElements;
      _recentCount = page.items.where((s) => !s.takenAt.isBefore(since)).length;
      _loaded = true;
    });
  }

  void _openDetail(int index) {
    _openSnapshot = _items.map((s) => s.id).toList();
    Navigator.of(context).push(
      appRoute(
        context,
        (_) => DetailScreen(
          items: List.of(_items),
          initialIndex: index,
          onViewing: _reveal,
        ),
      ),
    );
  }

  /// 상세에서 보고 있는 캡처의 타일이 보이게(Hero가 돌아올 자리). 빠졌으면 가장 가까운 이웃으로.
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

  GlobalKey _keyFor(int id) => _tileKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final window = windowLabel(widget.windowDays);
    final recent = _items.take(_recentCount).toList();
    final older = _items.skip(_recentCount).toList();
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
              Text('#${widget.tag}', style: AppText.title),
              if (_loaded) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  '최근 $window $_recentCount장 · 전체 $_total장',
                  style: AppText.caption.copyWith(color: AppColors.inkSub),
                ),
              ],
              const SizedBox(height: AppSpacing.s20),
              if (_loaded && _items.isEmpty)
                CaptureGrid(
                  items: const [],
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                ),
              if (recent.isNotEmpty) ...[
                _SectionTitle('최근 $window'),
                CaptureGrid(
                  items: recent,
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                ),
              ],
              if (older.isNotEmpty) ...[
                if (recent.isNotEmpty) const SizedBox(height: AppSpacing.s16),
                const _SectionTitle('그 전'),
                CaptureGrid(
                  items: older,
                  keyFor: _keyFor,
                  onOpen: _openDetail,
                  indexOffset: recent.length,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
    child: Semantics(header: true, child: Text(text, style: AppText.cardTitle)),
  );
}
