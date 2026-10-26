import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../data/device/settings_store.dart';
import '../data/remote/push.dart';
import '../widgets/app_button.dart';
import '../widgets/small_widgets.dart';

/// 설정: 이미지 분석 동의, 관심사 알림 받기([push]가 있을 때만).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.push});

  final SettingsStore settings;
  final PushClient? push;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    widget.settings.imageConsent().then((v) {
      if (mounted) setState(() => _consent = v ?? false);
    });
  }

  Future<void> _set(bool value) async {
    setState(() => _consent = value);
    await widget.settings.setImageConsent(value);
  }

  // 이미 영구 거부했으면 시스템 창이 뜨지 않으므로 휴대폰 설정으로 안내한다.
  Future<void> _requestNotification() async {
    final granted = await widget.push!.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? '관심사가 생기면 알려 드릴게요' : '휴대폰 설정 > 알림에서 Remine을 켜 주세요',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            8,
            4,
            AppSpacing.screenPadding,
            AppSpacing.s24,
          ),
          children: [
            Row(
              children: [
                const BackButtonCircle(),
                Expanded(
                  child: Text(
                    '설정',
                    style: AppText.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('이미지 분석', style: AppText.cardTitle),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          '글자가 적은 캡처는 작게 줄인 사진을 함께 보내요. 서버에 저장하지 않고, 민감한 정보나 전화번호가 보이는 캡처는 사진을 보내지 않아요. 끄면 글자만 보내요.',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Semantics(
                    label: '이미지 분석',
                    child: Switch(value: _consent, onChanged: _set),
                  ),
                ],
              ),
            ),
            if (widget.push != null) ...[
              const SizedBox(height: AppSpacing.s24),
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('관심사 알림', style: AppText.cardTitle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      '같은 걸 여러 번 캡처하면 일주일에 한 번까지 알려 드려요. 알림에는 태그만 담겨요.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    AppButton(
                      label: '알림 받기',
                      outlined: true,
                      onTap: _requestNotification,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
