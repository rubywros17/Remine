import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/remote/remote_services.dart';
import '../data/remote/sync_status.dart';
import 'pressable_scale.dart';

/// 홈 위쪽 안내 띠: 정리 중이면 진행, 연결 문제·일부 실패면 안내. 문제가 있으면 누르면 다시 시도한다.
/// 안내할 게 없으면 아무것도 그리지 않는다. 서버 결과를 못 받아도 홈은 저장해 둔 목록을 그대로 보여 준다.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.remote});

  final RemoteServices remote;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: remote.status,
      builder: (context, _) {
        final status = remote.status;
        final problem = status.issueMessage;
        final String? text = status.running
            ? '새 캡처를 정리하는 중이에요 · ${status.done}/${status.total}장'
            : problem;
        if (text == null) return const SizedBox.shrink();
        final retry = !status.running && status.issue != SyncIssue.none;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s16),
          child: PressableScale(
            onTap: retry ? () => remote.sync.run() : null,
            label: retry ? '$text 탭하면 다시 시도해요' : text,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: retry ? AppColors.lemon : AppColors.celadonSoft,
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Row(
                  children: [
                    Icon(
                      retry ? LucideIcons.cloudOff : LucideIcons.loader,
                      size: 18,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Text(
                        retry ? '$text\n탭하면 다시 시도해요' : text,
                        style: AppText.body.copyWith(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
