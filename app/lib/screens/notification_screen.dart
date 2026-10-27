import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/intro_choice_screen.dart';

/// 관심사 알림 안내 문구(해요체). 알림에 무엇이 담기는지 먼저 알린다.
const notificationTitle = '관심사가 생기면\n알려 드릴까요?';
const notificationBody = '같은 걸 여러 번 캡처하면 잊기 전에 다시 볼 수 있게 알려 드려요.';
const notificationPoints = [
  '알림은 일주일에 한 번까지만 와요.',
  '알림에는 태그만 담겨요. 캡처 속 글자는 담지 않아요.',
  '설정에서 언제든 끌 수 있어요.',
];

/// 첫 분석 완료 화면에서 [홈으로]를 누르면 한 번 보여 준다([SyncGate]).
/// [알림 받기]면 그다음에 시스템 권한 창이 뜬다(앱을 켜자마자 묻지 않는다).
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key, required this.onChoose});

  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) => IntroChoiceScreen(
    icon: LucideIcons.bell,
    title: notificationTitle,
    body: notificationBody,
    points: notificationPoints,
    yesLabel: '알림 받기',
    noLabel: '나중에',
    onChoose: onChoose,
  );
}
