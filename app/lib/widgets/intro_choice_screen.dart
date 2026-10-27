import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import 'app_button.dart';

/// 첫 실행 안내 화면의 공통 모양: 레몬 원 아이콘 → 큰 제목 → 본문 → 체크 항목 → 두 버튼.
/// 이미지 분석 동의([ConsentScreen])와 알림 안내([NotificationScreen])가 같이 쓴다.
class IntroChoiceScreen extends StatelessWidget {
  const IntroChoiceScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.points,
    required this.yesLabel,
    required this.noLabel,
    required this.onChoose,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  final String yesLabel;
  final String noLabel;
  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s24),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.lemon,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(icon, size: 26, color: AppColors.ink),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(title, style: AppText.display),
              const SizedBox(height: AppSpacing.s12),
              Text(body, style: AppText.body),
              const SizedBox(height: AppSpacing.s20),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          LucideIcons.check,
                          size: 18,
                          color: AppColors.celadonDeep,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(child: Text(point, style: AppText.body)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.s20),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  AppButton(label: yesLabel, onTap: () => onChoose(true)),
                  AppButton(
                    label: noLabel,
                    onTap: () => onChoose(false),
                    outlined: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
