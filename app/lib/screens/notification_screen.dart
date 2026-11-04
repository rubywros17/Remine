import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/device/settings_store.dart';
import '../data/remote/remote_services.dart';
import '../widgets/intro_choice_screen.dart';

/// 관심사 알림 안내 문구(해요체). 알림에 무엇이 담기는지 먼저 알린다.
const notificationTitle = '관심사가 생기면\n알려 드릴까요?';
const notificationBody = '같은 걸 여러 번 캡처하면 잊기 전에 다시 볼 수 있게 알려 드려요.';
const notificationPoints = [
  '알림은 일주일에 한 번까지만 와요.',
  '알림에는 태그만 담겨요. 캡처 속 글자는 담지 않아요.',
  '설정에서 언제든 끌 수 있어요.',
];

/// 첫 실행 때 이미지 동의 다음, 첫 분석 전에 한 번 묻는다(사진 권한 → 이미지 동의 → 알림 → 첫 분석).
/// 아직 고르지 않았고([SettingsStore.notificationsEnabled]가 null) 푸시가 있을 때만 이 화면을 먼저 보여 준다.
/// [알림 받기]면 그다음에 시스템 권한 창이 뜬다. [나중에]·뒤로 가기·권한 거부는 꺼짐으로 저장하고, 다시 묻지 않는다
/// (설정의 스위치로 켤 수 있다). 고른 값을 저장한 **뒤에** [child]로 넘어가서, 첫 기기 등록이 이 값으로 토큰을 싣는다.
class NotificationGate extends StatefulWidget {
  const NotificationGate({
    super.key,
    required this.remote,
    required this.settings,
    required this.child,
  });

  final RemoteServices remote;
  final SettingsStore settings;
  final Widget child;

  @override
  State<NotificationGate> createState() => _NotificationGateState();
}

class _NotificationGateState extends State<NotificationGate> {
  bool _loaded = false;
  bool _ask = false;
  bool _choosing = false; // 시스템 창이 떠 있는 동안 두 번 누르지 않게

  @override
  void initState() {
    super.initState();
    if (widget.remote.push == null) {
      _loaded = true;
      return;
    }
    widget.settings.notificationsEnabled().then((v) {
      if (mounted) {
        setState(() {
          _ask = v == null;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _choose(bool want) async {
    if (_choosing) return;
    _choosing = true;
    final granted = want && await widget.remote.push!.requestPermission();
    await widget.remote.sync.setNotifications(granted);
    if (mounted) setState(() => _ask = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_ask) return widget.child;
    return PopScope(
      // 고르지 않고 나가면(뒤로 가기) 꺼짐으로 저장하고 넘어간다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _choose(false);
      },
      child: NotificationScreen(onChoose: _choose),
    );
  }
}

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
