import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'app_button.dart';

/// 첫 동기화가 끝난 뒤 한 번 띄우는 알림 안내 시트. [알림 받기]면 true, [나중에]·닫기면 false/null.
/// 시스템 권한 창은 이 시트에서 "받기"를 고른 뒤에만 띄운다(앱을 켜자마자 묻지 않는다).
Future<bool?> showNotificationSheet(BuildContext context) {
  final duration = AppMotion.duration(context, MotionDuration.slow);
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
      curve: AppMotion.emphasized,
    ),
    builder: (context) => DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '관심사가 생기면 알려 드릴까요?',
                style: AppText.cardTitle.copyWith(fontSize: 22),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                '같은 걸 여러 번 캡처하면 일주일에 한 번까지 알려 드려요. 알림에는 태그만 담겨요.',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.s20),
              AppButton(
                label: '알림 받기',
                onTap: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.s8),
              AppButton(
                label: '나중에',
                outlined: true,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
