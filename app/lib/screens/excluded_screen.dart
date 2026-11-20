import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/privacy/local_verdict_store.dart';
import '../data/device/trash_store.dart';
import '../data/remine_store.dart';
import '../widgets/app_button.dart';
import '../widgets/gallery_thumb.dart';
import '../widgets/selectable_thumb.dart';
import '../widgets/small_widgets.dart';

/// 판정 사유 코드 → 화면에 보이는 말. 코드만 저장돼 있어서 값은 보여 줄 수 없다.
String reasonLabel(String code) => switch (code) {
  'SSN' => '주민등록번호',
  'CARD' => '카드번호',
  'ACCOUNT' => '계좌번호',
  'OTP' => '인증번호',
  'PASSWORD' => '비밀번호',
  'APP_FINANCIAL' => '금융 앱',
  'APP_PRIVATE' => '통화·연락처 앱',
  'APP_OWN' => 'Remine 화면',
  _ => code,
};

/// "분석 제외" 목록: 숨김 판정(민감 정보·금융 앱·Remine 자기 캡처) 중 휴지통에 없는 것. 홈 알약 개수도 이걸 센다.
Future<List<StoredVerdict>> loadExcluded(
  LocalVerdictStore verdicts,
  TrashStore trash,
) async {
  final trashed = {for (final t in await trash.hidden()) t.assetId};
  return [
    for (final v in await verdicts.deviceOnly(hidden: true))
      if (!trashed.contains(v.assetId)) v,
  ];
}

/// "분석 제외": 서버로 보내지 않고 기기에서만 분류한 숨김 캡처(강한 민감 정보, 은행·증권·카드 앱, Remine 화면)를 모아 본다.
/// 정리 묶음 화면처럼 탭으로 골라 [휴지통으로 N장] → 되돌리기. 민감 캡처가 섞여 있어 처음엔 아무것도 고르지 않는다.
class ExcludedScreen extends StatefulWidget {
  const ExcludedScreen({
    super.key,
    required this.verdicts,
    required this.trash,
    required this.reader,
  });

  final LocalVerdictStore verdicts;
  final TrashStore trash;
  final GalleryReader reader;

  @override
  State<ExcludedScreen> createState() => _ExcludedScreenState();
}

class _ExcludedScreenState extends State<ExcludedScreen> {
  List<StoredVerdict>? _items;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await loadExcluded(widget.verdicts, widget.trash);
    if (!mounted) return;
    setState(() {
      _items = items;
      _selected.retainAll({for (final v in items) v.assetId});
    });
  }

  bool get _allSelected => _items != null && _selected.length == _items!.length;

  void _toggle(String assetId) => setState(() {
    if (!_selected.remove(assetId)) _selected.add(assetId);
  });

  /// 고른 장을 휴지통으로(기기 판정이라 저장소 id는 `-localId`) → 목록에서 빼고 → 되돌리기 안내.
  Future<void> _trashSelected() async {
    final store = RemineScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reduced = AppMotion.reduced(context);
    final ids = [
      for (final v in _items ?? const <StoredVerdict>[])
        if (_selected.contains(v.assetId)) -v.localId,
    ];
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    for (final id in ids) {
      await store.trash(id);
    }
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ids.length}장을 휴지통으로 옮겼어요',
          style: AppText.label.copyWith(color: AppColors.white),
        ),
        duration: AppGesture.undoDuration,
        persist: false,
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkGray,
        shape: const StadiumBorder(),
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.s16,
        ),
        action: SnackBarAction(
          label: '되돌리기',
          textColor: AppColors.lemon,
          onPressed: () async {
            for (final id in ids) {
              await store.restore(id);
            }
            await _load();
          },
        ),
      ),
      snackBarAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
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
                      '분석 제외',
                      style: AppText.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.s4,
                AppSpacing.screenPadding,
                AppSpacing.s12,
              ),
              child: Text(
                '서버로 보내지 않고 이 폰 안에서만 분류한 캡처예요.',
                style: AppText.caption,
              ),
            ),
            if (items != null && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  0,
                  AppSpacing.screenPadding,
                  AppSpacing.s12,
                ),
                child: AppButton(
                  label: _allSelected ? '선택 해제' : '전체 선택',
                  outlined: true,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          if (_allSelected) {
                            _selected.clear();
                          } else {
                            _selected.addAll(items.map((v) => v.assetId));
                          }
                        }),
                ),
              ),
            Expanded(child: _body(items)),
            if (_selected.isNotEmpty) _bar(),
          ],
        ),
      ),
    );
  }

  Widget _body(List<StoredVerdict>? items) {
    if (items == null) return const SizedBox.shrink();
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Text(
            '분석에서 제외된 캡처가 없어요.',
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
        mainAxisSpacing: AppSpacing.s12,
        crossAxisSpacing: 6,
        childAspectRatio: 0.62,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ExcludedTile(
        reader: widget.reader,
        verdict: items[i],
        selected: _selected.contains(items[i].assetId),
        onTap: _busy ? null : () => _toggle(items[i].assetId),
      ),
    );
  }

  Widget _bar() => SizedBox(
    width: double.infinity,
    child: Material(
      color: AppColors.chip,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Center(
          child: AppButton(
            label: '휴지통으로 ${_selected.length}장',
            dark: true,
            onTap: _busy ? null : _trashSelected,
          ),
        ),
      ),
    ),
  );
}

class _ExcludedTile extends StatelessWidget {
  const _ExcludedTile({
    required this.reader,
    required this.verdict,
    required this.selected,
    required this.onTap,
  });

  final GalleryReader reader;
  final StoredVerdict verdict;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reasons = verdict.reasons.map(reasonLabel).join(' · ');
    return Semantics(
      button: true,
      selected: selected,
      label: '$reasons 캡처',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('excluded-${verdict.assetId}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableThumb(
                selected: selected,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  child: SizedBox.expand(
                    child: GalleryThumb(
                      reader: reader,
                      photoId: verdict.assetId,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              reasons,
              style: AppText.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
