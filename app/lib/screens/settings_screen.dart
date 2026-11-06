import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_trash.dart';
import '../data/device/settings_store.dart';
import '../data/remote/remote_services.dart';
import '../widgets/small_widgets.dart';
import 'trash_screen.dart';

/// 설정: 이미지 분석 동의, 관심사 알림 받기(서버 연동 + 푸시가 있을 때만), 휴지통.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.remote,
    this.trash,
  });

  final SettingsStore settings;
  final RemoteServices? remote;
  final DeviceTrash? trash;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _consent = false;
  bool _notify = false;
  ScaffoldMessengerState? _messenger;

  bool get _hasPush => widget.remote?.push != null;

  @override
  void initState() {
    super.initState();
    widget.settings.imageConsent().then((v) {
      if (mounted) setState(() => _consent = v ?? false);
    });
    _loadNotify();
  }

  // 켜 두었어도 휴대폰 설정에서 권한을 끄면 알림이 안 오므로 꺼짐으로 보여 준다.
  Future<void> _loadNotify() async {
    final push = widget.remote?.push;
    if (push == null) return;
    final on =
        await widget.settings.notificationsEnabled() == true &&
        await push.permissionGranted();
    if (mounted) setState(() => _notify = on);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose에서는 context를 쓸 수 없어서 미리 잡아 둔다.
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // 앱 전체가 같은 ScaffoldMessenger를 쓰므로, 나가면서 닫지 않으면 홈까지 따라간다.
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  Future<void> _set(bool value) async {
    setState(() => _consent = value);
    await widget.settings.setImageConsent(value);
  }

  /// 켜기: 권한을 확인·요청하고, 허용됐을 때만 켠다(서버에 토큰 등록). 끄기: 서버에서 토큰을 지운다.
  Future<void> _setNotify(bool value) async {
    final remote = widget.remote!;
    if (!value) {
      setState(() => _notify = false);
      await remote.sync.setNotifications(false);
      return;
    }
    final push = remote.push!;
    final granted =
        await push.permissionGranted() || await push.requestPermission();
    if (!mounted) return;
    if (!granted) {
      // 영구 거부면 시스템 창이 뜨지 않는다 → 휴대폰 설정으로 안내한다.
      _messenger?.hideCurrentSnackBar();
      _messenger?.showSnackBar(
        SnackBar(
          content: const Text('휴대폰 설정에서 알림을 켜 주세요'),
          duration: const Duration(seconds: 3),
          persist: false, // 액션이 있으면 기본값이 '계속 띄움'이라 명시한다
          action: SnackBarAction(
            label: '설정 열기',
            onPressed: push.openSystemSettings,
          ),
        ),
      );
      return;
    }
    setState(() => _notify = true);
    await remote.sync.setNotifications(true);
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
            const SizedBox(height: AppSpacing.s8),
            _SwitchRow(
              title: '이미지 분석',
              body:
                  '글자가 적은 캡처는 작게 줄인 사진을 함께 보내요.\n'
                  '서버에 저장하지 않고, 민감한 정보나 전화번호가 보이는 캡처는 사진을 보내지 않아요.\n'
                  '끄면 글자만 보내요.',
              value: _consent,
              onChanged: _set,
            ),
            if (_hasPush) ...[
              const SizedBox(height: AppSpacing.s4),
              _SwitchRow(
                title: '알림 받기',
                body:
                    '같은 걸 여러 번 캡처하면 일주일에 한 번까지 알려 드려요.\n'
                    '알림에는 태그만 담겨요.',
                value: _notify,
                onChanged: _setNotify,
              ),
            ],
            if (widget.trash != null) ...[
              const SizedBox(height: AppSpacing.s4),
              _TrashRow(trash: widget.trash!),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({required this.trash});

  final DeviceTrash trash;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: '휴지통',
      body: '버린 캡처를 되살리거나 갤러리에서 지워요.',
      onTap: () =>
          Navigator.of(context)
              .push(appRoute(context, (_) => TrashScreen(trash: trash))),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 줄 어디를 눌러도 스위치가 바뀐다(ListTile과 같은 동작).
    return _SettingsRow(
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
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.body,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
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
                    const SizedBox(height: AppSpacing.s4),
                    Text(body, style: AppText.caption),
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
