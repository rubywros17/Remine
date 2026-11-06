import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/device/device_trash.dart';
import '../data/device/trash_store.dart';
import '../data/remine_store.dart';
import '../widgets/app_button.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/selectable_thumb.dart';
import '../widgets/small_widgets.dart';

/// 안내 문구. 앱 휴지통과 갤러리 휴지통이 다르다는 것을 알려 준다.
const trashGalleryNote = '갤러리에서 삭제하면 갤러리 휴지통으로 이동해요';

/// 설정 > 휴지통: 스와이프로 버린 캡처를 버린 날짜순으로 보여 준다. 카드를 고르면 되살리거나 갤러리에서 지울 수 있다.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.trash});

  final DeviceTrash trash;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<TrashedShot>? _shots;
  bool _canDelete = false;
  bool _busy = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
    widget.trash.reader.canMoveToTrash().then((v) {
      if (mounted) setState(() => _canDelete = v);
    });
  }

  Future<void> _load() async {
    final shots = await widget.trash.store.all();
    if (!mounted) return;
    setState(() {
      _shots = shots;
      _selected.retainAll({for (final s in shots) s.assetId});
    });
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  /// 작업 중에는 버튼을 막고, 끝나면 다시 읽어 홈 개수까지 갱신한다.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        RemineScope.maybeOf(context)?.refresh();
        await _load();
      }
    }
  }

  Future<void> _restore() =>
      _run(() => widget.trash.restore(_selected.toList()));

  Future<void> _delete(List<String> ids) =>
      _run(() => widget.trash.deleteFromGallery(ids));

  @override
  Widget build(BuildContext context) {
    final shots = _shots;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                4,
                AppSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  const BackButtonCircle(),
                  Expanded(
                    child: Text(
                      '휴지통 ${shots?.length ?? 0}장',
                      style: AppText.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (shots != null && shots.isNotEmpty && _canDelete) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s12,
                  AppSpacing.screenPadding,
                  0,
                ),
                child: AppButton(
                  label: '갤러리에서도 삭제',
                  onTap: _busy
                      ? null
                      : () => _delete(
                          _selected.isNotEmpty
                              ? _selected.toList()
                              : [for (final s in shots) s.assetId],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s8,
                  AppSpacing.screenPadding,
                  AppSpacing.s12,
                ),
                child: Text(trashGalleryNote, style: AppText.caption),
              ),
            ] else
              const SizedBox(height: AppSpacing.s12),
            Expanded(child: _grid(shots)),
            if (_selected.isNotEmpty) _selectionBar(),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<TrashedShot>? shots) {
    if (shots == null) return const SizedBox.shrink();
    if (shots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Text(
            '삭제한 스크린샷이 없어요',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.s24,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.72,
      ),
      itemCount: shots.length,
      itemBuilder: (_, i) {
        final shot = shots[i];
        final on = _selected.contains(shot.assetId);
        return Semantics(
          button: true,
          selected: on,
          label: '${shot.category.label} 캡처',
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('trash-${shot.assetId}'),
            onTap: _busy ? null : () => _toggle(shot.assetId),
            child: SelectableThumb(
              selected: on,
              child: CaptureThumb(
                key: ValueKey(shot.assetId),
                assetId: shot.assetId,
                seed: shot.assetId.hashCode.abs(),
                radius: 12,
                size: 240,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _selectionBar() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.chip,
        // 아주 작은 화면에서도 격자가 밀려나지 않게 화면의 40%까지만 쓰고 넘치면 스크롤한다.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              alignment: WrapAlignment.center,
              children: [
                AppButton(
                  label: '되살리기',
                  outlined: true,
                  onTap: _busy ? null : _restore,
                ),
                if (_canDelete)
                  AppButton(
                    label: '갤러리에서 삭제',
                    outlined: true,
                    onTap: _busy ? null : () => _delete(_selected.toList()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
