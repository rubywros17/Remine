import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 설정·예전 스크린샷 화면의 목록 줄. [Flutter 메모] 위젯을 여러 화면이 같이 쓰도록 widgets/로 뺐다.
class SwitchSettingsRow extends StatelessWidget {
  const SwitchSettingsRow({
    super.key,
    required this.title,
    this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 줄 어디를 눌러도 스위치가 바뀐다(ListTile과 같은 동작).
    return SettingsRow(
      title: title,
      body: body,
      onTap: () => onChanged(!value),
      trailing: Semantics(
        label: title,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// 설정 한 줄: 제목 · 설명 (+ 오른쪽 위젯). 누르면 셀라돈 톤 하이라이트·물결이 보인다.
///
/// [Flutter 메모] InkWell은 가장 가까운 Material 위에 물결을 그린다. 배경이 없는 투명 Material을 바로 위에 둔다.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.body,
    this.bodySpan,
    required this.onTap,
    this.trailing,
  });

  final String title;

  /// 설명. 일부만 굵게 하려면 [bodySpan]. 둘 다 없으면 제목만.
  final String? body;
  final InlineSpan? bodySpan;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.tile);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        highlightColor: AppColors.pressHighlight,
        splashColor: AppColors.pressSplash,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.cardTitle),
                    if (body != null || bodySpan != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text.rich(
                        bodySpan ?? TextSpan(text: body),
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.s12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 줄 오른쪽 "›"(다른 화면으로 넘어간다).
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, right: 4),
    child: Text('›', style: AppText.label.copyWith(color: AppColors.inkSub)),
  );
}
