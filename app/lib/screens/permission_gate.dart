import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/device/gallery_reader.dart';
import '../widgets/app_button.dart';

/// 사진 접근 권한에 따라 화면을 가른다.
/// 허용 → [child], 일부만 허용 → 안내 띠 + [child], 거부 → 안내 화면(설정 열기).
///
/// [Flutter 메모] WidgetsBindingObserver는 앱이 백그라운드에서 돌아올 때(설정을 다녀온 뒤)를 알려 준다.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.reader, required this.child});

  final GalleryReader reader;
  final Widget child;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  GalleryAccess? _access;

  /// 권한을 한 번이라도 요청했는지. 요청했는데도 거부면 팝업이 더 안 뜰 수 있어 설정 열기를 앞세운다.
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool request = false}) async {
    final access = await widget.reader.access(request: request);
    if (request) _requested = true;
    if (mounted) setState(() => _access = access);
  }

  Future<void> _reselect() async {
    await widget.reader.reselect();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) {
      return const Scaffold(backgroundColor: AppColors.background);
    }
    return switch (access) {
      GalleryAccess.authorized => widget.child,
      GalleryAccess.limited => Column(
        children: [
          _LimitedBanner(onReselect: _reselect),
          // 띠가 상태 표시줄 영역을 이미 차지했으니 아래 화면은 윗쪽 안전 영역을 또 잡지 않는다.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      ),
      GalleryAccess.denied => _DeniedView(
        requested: _requested,
        onRequest: () => _check(request: true),
        onSettings: widget.reader.openSettings,
      ),
    };
  }
}

class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onReselect});

  final VoidCallback onReselect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lemon,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.s12,
            AppSpacing.screenPadding,
            AppSpacing.s12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '고른 사진만 보여. 새 스크린샷은 자동으로 가져올 수 없어.',
                  style: AppText.caption.copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              AppButton(label: '다시 고르기', onTap: onReselect, outlined: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView({
    required this.requested,
    required this.onRequest,
    required this.onSettings,
  });

  final bool requested;
  final VoidCallback onRequest;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: box.maxHeight - AppSpacing.screenPadding * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.lemon,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(
                        LucideIcons.images,
                        size: 28,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  const Text('사진을 볼 수 있어야 해', style: AppText.display),
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    requested
                        ? '권한 창이 더 안 뜨면 설정에서 직접 허용해줘. 사진과 글자는 이 폰 안에서만 처리돼.'
                        : '스크린샷을 정리하려면 사진 접근을 허용해줘. 사진과 글자는 이 폰 안에서만 처리돼.',
                    style: AppText.body,
                  ),
                  const SizedBox(height: AppSpacing.s32),
                  Wrap(
                    spacing: AppSpacing.s12,
                    runSpacing: AppSpacing.s12,
                    children: [
                      AppButton(
                        label: '권한 허용',
                        onTap: onRequest,
                        outlined: requested,
                      ),
                      AppButton(
                        label: '설정 열기',
                        onTap: onSettings,
                        outlined: !requested,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
