import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/remote/remote_services.dart';
import '../data/remote/sync_status.dart';
import 'pressable_scale.dart';

/// 홈 위쪽 안내 띠: 정리 중이면 진행, 연결 문제·일부 실패면 한 줄 "서버에 연결하지 못했어요 · 다시 시도"(누르면 다시 시도). 안내할 게 없으면 아무것도 그리지 않는다.
/// 서버 결과를 못 받아도 홈은 저장해 둔 목록을 그대로 보여 준다.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.remote});

  final RemoteServices remote;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: remote.status,
      builder: (context, _) {
        final status = remote.status;
        final retry = !status.running && status.issue != SyncIssue.none;
        // 문제가 있으면 한 줄로 짧게 "서버에 연결하지 못했어요 · 다시 시도", 정리 중이면 진행만.
        final String? text = status.running
            ? '새 캡처를 정리하는 중이에요 · ${status.done}/${status.total}장'
            : (retry ? '${status.bannerMessage} · 다시 시도' : null);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: PressableScale(
            onTap: retry ? () => remote.sync.run() : null,
            label: text,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: retry ? AppColors.lemon : AppColors.celadonSoft,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        retry ? LucideIcons.cloudOff : LucideIcons.loader,
                        size: 16,
                        color: AppColors.ink,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
