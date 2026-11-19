import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/older_progress.dart';
import '../data/device/settings_store.dart';
import '../data/remote/remote_services.dart';
import '../widgets/settings_rows.dart';
import '../widgets/small_widgets.dart';
import 'older_range_screen.dart';
import 'older_shots_screen.dart';
import 'older_texts.dart';

/// 설정: 이미지 분석 동의, 관심사 알림 받기(서버 연동 + 푸시가 있을 때만), 예전 스크린샷 정리(기기 모드).
/// 휴지통은 정리 탭에 있다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.remote});

  final SettingsStore settings;
  final RemoteServices? remote;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _consent = false;
  bool _notify = false;
  ScaffoldMessengerState? _messenger;

  bool get _hasPush => widget.remote?.push != null;

  /// 예전 스크린샷 현황(기기 모드에서만, 갤러리 count라 빠르다). 세기 전·크롬은 null → 줄을 숨긴다.
  OlderOverview? _older;
  bool _olderLoading = false;

  Future<void> _loadOlder() async {
    final device = DeviceScope.maybeOf(context);
    if (device == null || _olderLoading) return;
    _olderLoading = true;
    final o = await loadOlderOverview(device.reader, widget.settings);
    _olderLoading = false;
    if (mounted) setState(() => _older = o);
  }

  Future<void> _openOlder() async {
    final device = DeviceScope.maybeOf(context);
    final o = _older;
    if (device == null || o == null) return;
    await Navigator.of(context).push<void>(
      appRoute(
        context,
        (_) => o.chosen
            ? OlderShotsScreen(
                settings: widget.settings,
                reader: device.reader,
                remote: widget.remote,
              )
            : OlderRangeScreen(
                settings: widget.settings,
                reader: device.reader,
                fromSettings: true,
              ),
      ),
    );
    _loadOlder(); // 범위·스위치를 바꿨을 수 있다
  }

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
    if (_older == null) _loadOlder();
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
            SwitchSettingsRow(
              title: '이미지 분석',
              body:
                  '글자가 적은 캡처는 작게 줄인 사진을 함께 보내요.\n'
                  '서버에 저장하지 않고, 민감한 정보나 전화번호가 보이는 캡처는 사진을 보내지 않아요.\n'
                  '해제 시 글자만 보내요.',
              value: _consent,
              onChanged: _set,
            ),
            if (_hasPush) ...[
              const SizedBox(height: AppSpacing.s4),
              SwitchSettingsRow(
                title: '알림 받기',
                body:
                    '같은 걸 여러 번 캡처하면 일주일에 한 번까지 알려 드려요.\n'
                    '알림에는 태그만 담겨요.',
                value: _notify,
                onChanged: _setNotify,
              ),
            ],
            if (_older case final o?) ...[
              const SizedBox(height: AppSpacing.s4),
              SettingsRow(
                title: OlderTexts.settingsRow,
                body: o.chosen ? null : OlderTexts.pickRange,
                bodySpan: o.chosen
                    ? TextSpan(
                        children: [
                          const TextSpan(text: OlderTexts.settingsBodyBefore),
                          TextSpan(
                            text: OlderTexts.shots(o.unseen),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const TextSpan(text: OlderTexts.settingsBodyRest),
                        ],
                      )
                    : null,
                onTap: _openOlder,
                trailing: const SettingsChevron(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
