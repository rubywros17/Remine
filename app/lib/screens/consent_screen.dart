import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/device/settings_store.dart';
import '../widgets/app_button.dart';

/// 이미지 분석 동의 문구. 개인정보 문구는 해요체로 쓴다(docs/design.md).
const consentTitle = '글자가 적은 캡처는\n사진으로 분석할게요';
const consentBody =
    '글자가 거의 없는 캡처는 글자만으로는 분류하기 어려워요.\n동의하면 이런 캡처만 작게 줄인 사진을 분석에 보내요.';
const consentPoints = [
  '분석에 쓴 사진은 서버에 저장하지 않아요.',
  '민감한 정보나 전화번호가 보이는 캡처는\n사진을 보내지 않아요.',
  '설정에서 언제든 끌 수 있어요. 끄면 글자만 보내요.',
];

/// 첫 실행 때 한 번 묻는다. 아직 고르지 않았으면([SettingsStore.imageConsent]가 null) [ConsentGate]가 이 화면을 먼저 보여 준다.
/// **선택하지 않고 나가면(뒤로 가기) 거부로 저장하고 앱으로 들어간다.**
class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.settings, required this.child});

  final SettingsStore settings;
  final Widget child;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  bool _loaded = false;
  bool? _consent;

  @override
  void initState() {
    super.initState();
    widget.settings.imageConsent().then((v) {
      if (mounted) {
        setState(() {
          _consent = v;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _choose(bool value) async {
    await widget.settings.setImageConsent(value);
    if (mounted) setState(() => _consent = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_consent != null) return widget.child;
    return PopScope(
      // 고르지 않고 나가면(뒤로 가기) 거부로 저장하고 앱으로 넘어간다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _choose(false);
      },
      child: ConsentScreen(onChoose: _choose),
    );
  }
}

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onChoose});

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
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(
                    LucideIcons.imageUp,
                    size: 26,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Text(consentTitle, style: AppText.display),
              const SizedBox(height: AppSpacing.s12),
              Text(consentBody, style: AppText.body),
              const SizedBox(height: AppSpacing.s20),
              for (final point in consentPoints)
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
                  AppButton(label: '동의할래요', onTap: () => onChoose(true)),
                  AppButton(
                    label: '안 할래요',
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
