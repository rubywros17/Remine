import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/remote/remote_services.dart';
import '../data/remote/sync_status.dart';
import '../screens/analysis_screen.dart';
import 'pressable_scale.dart';

/// 홈 위쪽 안내 띠: 정리 중이면 진행(누르면 분석 진행 화면), 연결 문제·일부 실패면 한 줄 "서버에 연결하지 못했어요 · 다시 시도"(누르면 다시 시도). 안내할 게 없으면 아무것도 그리지 않는다.
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
        if (text == null) {
          // 디버그에서 자동 동기화를 껐을 때만: 왜 새 캡처가 안 올라가는지 알 수 있게 작게
          return remote.sync.autoSync
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s8),
                  child: Text(
                    '자동 정리 꺼짐(디버그)',
                    style: AppText.caption.copyWith(color: AppColors.inkSub),
                  ),
                );
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: PressableScale(
            onTap: retry
                ? () => remote.sync.run()
                : () => _openAnalysis(context),
            // 화면 읽기: 진행 숫자도 같이 읽고, 누르면 무엇이 열리는지 알린다.
            label: retry ? text : '$text, 분석 진행 화면 열기',
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
                      if (!retry)
                        const Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: AppColors.ink,
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

  /// 첫 분석과 같은 진행 화면. 보는 중에 끝나면 그 자리에서 완료 상태로 바뀌고, 홈 버튼은 닫기다.
  void _openAnalysis(BuildContext context) => Navigator.of(context).push(
    appRoute(
      context,
      (route) => AnalysisScreen(
        status: remote.status,
        onHome: () => Navigator.of(route).pop(),
      ),
    ),
  );
}
