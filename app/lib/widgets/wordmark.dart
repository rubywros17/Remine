import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 워드마크 `re:mine`. 콜론만 딥 셀라돈, 나머지는 [color]. 화면 읽기에는 "Remine"으로 읽힌다.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.color = AppColors.ink});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppText.brand(color: color);
    return Semantics(
      label: 'Remine',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 're'),
            TextSpan(
              text: ':',
              style: style.copyWith(color: AppColors.celadonDeep),
            ),
            const TextSpan(text: 'mine'),
          ],
        ),
      ),
    );
  }
}
