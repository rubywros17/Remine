import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/device_trash.dart';
import 'trash_screen.dart';

/// 정리 탭(임시): 휴지통으로 가는 줄 하나. 정리 제안은 나중에 이 화면에 붙는다.
/// 휴지통은 기기 모드에서만 있어서, 가짜 데이터 모드에서는 줄을 숨긴다(설정 톱니와 같다).
class TidyScreen extends StatelessWidget {
  const TidyScreen({super.key, this.active = true});

  /// 탭이 보이는 중인지. 다시 보일 때 휴지통 장수를 새로 읽는다.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final trash = DeviceScope.maybeOf(context)?.trash;
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
          Text('정리', style: AppText.title),
          const SizedBox(height: AppSpacing.s8),
          Text('지워도 될 만한 캡처를 모아 드릴게요', style: AppText.caption),
          const SizedBox(height: AppSpacing.s24),
          if (trash != null) ...[
            _TrashRow(trash: trash, active: active),
            const SizedBox(height: AppSpacing.s16),
          ],
          Text(
            '정리 제안은 곧 생겨요',
            style: AppText.caption.copyWith(color: AppColors.inkSub),
          ),
        ],
      ),
    );
  }
}

/// 아이콘 + "휴지통" + 장수 + ›. 누르면 설정 > 휴지통과 같은 화면.
class _TrashRow extends StatefulWidget {
  const _TrashRow({required this.trash, required this.active});

  final DeviceTrash trash;
  final bool active;

  @override
  State<_TrashRow> createState() => _TrashRowState();
}

class _TrashRowState extends State<_TrashRow> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TrashRow old) {
    super.didUpdateWidget(old);
    // 다른 탭(상세에서 버리기 등)에서 바뀌었을 수 있으니 탭에 들어올 때 다시 센다.
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final n = (await widget.trash.store.all()).length;
    if (mounted) setState(() => _count = n);
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(appRoute(context, (_) => TrashScreen(trash: widget.trash)));
    _load(); // 휴지통에서 되살리거나 지웠을 수 있다
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.tile);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _open,
        borderRadius: radius,
        highlightColor: AppColors.pressHighlight,
        splashColor: AppColors.pressSplash,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Icon(LucideIcons.trash2, size: 22, color: AppColors.ink),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  '휴지통',
                  style: AppText.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_count != null)
                Text(
                  '$_count장',
                  style: AppText.caption.copyWith(color: AppColors.inkSub),
                ),
              const SizedBox(width: AppSpacing.s4),
              const Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: AppColors.inkSub,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
