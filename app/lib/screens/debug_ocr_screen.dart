import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../app.dart';
import '../core/tokens.dart';
import '../data/device/device_capture_service.dart';
import '../data/device/device_services.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/ocr_export.dart';
import '../data/device/ocr_store.dart';
import '../data/device/privacy/app_rules.dart';
import '../data/remine_store.dart';
import '../data/remote/api_client.dart';
import '../data/remote/sync_status.dart';
import '../widgets/app_button.dart';
import '../widgets/gallery_thumb.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/selectable_thumb.dart';
import '../widgets/small_widgets.dart';

/// [디버그 전용] 고른 사진의 OCR 결과를 JSON으로 내보내 ML Kit 기준으로 다시 측정한다.
/// 진입점이 `kDebugMode`로 막혀 있어 릴리스 빌드에는 들어가지 않는다(트리 셰이킹).
/// 화면에는 글자 수·장수만 보이고 OCR 원문은 띄우지 않는다.
class DebugOcrScreen extends StatefulWidget {
  const DebugOcrScreen({super.key, required this.services, this.now});

  final DeviceServices services;
  final DateTime Function()? now;

  @override
  State<DebugOcrScreen> createState() => _DebugOcrScreenState();
}

class _DebugOcrScreenState extends State<DebugOcrScreen> {
  List<GalleryAlbum> _albums = const [];
  String? _albumId;
  List<GalleryPhoto> _photos = const [];
  final Set<String> _selected = {};
  List<OcrRecord> _records = const [];

  bool _loading = true;
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  String _status = '';

  DeviceCaptureService get _capture => widget.services.capture;
  DateTime _now() => (widget.now ?? DateTime.now)();

  /// 서버 기기 id 줄. 실기기에서 `curl -H "X-Device-Id: N"`으로 서버 응답을 직접 볼 때 쓴다.
  String _deviceIdLine = '';
  int? _deviceId;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final remote = widget.services.remote;
    final id = await remote?.state.deviceId();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
      _deviceIdLine = remote == null
          ? '서버 연동 꺼짐 (가짜/기기 데이터만)'
          : '서버 기기 id: ${id ?? '없음(아직 등록 전)'}';
    });
  }

  Future<void> _copyDeviceId() async {
    final id = _deviceId;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: '$id'));
    if (!mounted) return;
    setState(() => _status = '기기 id $id 복사했어.');
  }

  /// 서버(dev 프로필)가 이 기기에 관심사 알림 1건을 보낸다. 앱이 앞에 있으면 FCM 알림이 화면에 안 뜨므로
  /// 서버가 5초 기다렸다 보낸다. 요청은 지금 바로 나가서, 앱을 내려도(안드로이드가 앱을 멈춰도) 끊기지 않는다.
  /// 자동 동기화를 껐을 때(`AUTO_SYNC=false`) 손으로 한 번 돌린다. 켜져 있어도 진행 중이면 그걸 기다린다.
  Future<void> _syncNow() async {
    final remote = widget.services.remote;
    if (remote == null) return;
    setState(() => _status = '동기화하는 중…');
    await remote.sync.run();
    if (!mounted) return;
    final s = remote.status;
    setState(
      () => _status = s.issue == SyncIssue.none
          ? '동기화 끝(${s.total}장 처리).'
          : '동기화 멈춤: ${s.bannerMessage}',
    );
  }

  /// 상세 "위로 밀어 삭제" 안내의 '봤음' 기록만 지운다.
  Future<void> _resetTutorial() async {
    await widget.services.settings.clearSwipeTutorialSeen();
    if (mounted) setState(() => _status = '상세에 들어가면 튜토리얼이 다시 떠.');
  }

  /// 이미지 동의·알림 선택만 지우고 첫 실행 게이트부터 다시 그린다. 분석·기기 id·전송 기록은 그대로(재분석 없음).
  Future<void> _resetFirstRun() async {
    await widget.services.settings.clearFirstRunChoices();
    if (mounted) RemineApp.restartFirstRun(context);
  }

  Future<void> _sendTestPush() async {
    final sync = widget.services.remote?.sync;
    if (sync == null) return;
    setState(() => _status = '5초 뒤에 보낼게. 앱을 내려 둬(앱이 앞에 있으면 알림이 안 보여).');
    String result;
    try {
      result = switch (await sync.sendTestPush(delaySeconds: 5)) {
        'SENT' => '테스트 알림 보냈어.',
        'INVALID_TOKEN' => 'FCM이 이 기기 토큰을 모른대. 알림을 껐다 켜 줘.',
        final r => '서버가 보내지 못했어($r). 서버 로그의 code를 봐 줘.',
      };
    } on ApiException catch (e) {
      result = switch (e.statusCode) {
        404 => '서버를 dev 프로필로 켜 줘(--spring.profiles.active=dev).',
        409 => '설정에서 알림을 먼저 켜 줘.',
        503 => '서버에 Firebase 키가 없어(remine.fcm.credentials-file).',
        _ => '보내지 못했어(${e.failure.name}).',
      };
    }
    if (mounted) setState(() => _status = result);
  }

  Future<void> _loadAlbums() async {
    final albums = await widget.services.reader.albums();
    if (!mounted) return;
    _albums = albums;
    if (albums.isEmpty) {
      setState(() {
        _loading = false;
        _status = '볼 수 있는 앨범이 없어.';
      });
      return;
    }
    await _selectAlbum(albums.first.id);
  }

  Future<void> _selectAlbum(String id) async {
    setState(() {
      _albumId = id;
      _loading = true;
      _selected.clear();
      _records = const [];
      _status = '';
    });
    final photos = await _capture.recent(id);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  Future<void> _run() async {
    final targets = [
      for (final p in _photos)
        if (_selected.contains(p.id)) p,
    ];
    if (targets.isEmpty) return;
    setState(() {
      _running = true;
      _cancel = false;
      _done = 0;
      _status = '';
    });
    final run = await _capture.run(
      targets,
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
      isCancelled: () => _cancel,
    );
    if (!mounted) return;
    RemineScope.maybeOf(context)?.refresh(); // 홈 집계에 기기 안 분류 결과 반영
    setState(() {
      _running = false;
      _records = run.records;
      _status =
          '${run.records.length}장 완료 · 이전 결과 재사용 ${run.skipped}장 · 앱 이름으로 OCR 생략 ${run.byApp}장 · 실패 ${run.failed}장';
    });
  }

  Future<void> _export() async {
    final dir = await widget.services.exportDir();
    final file = await OcrExport.write(
      dir,
      _records,
      engine: _capture.ocr.name,
      now: _now(),
    );
    if (!mounted) return;
    setState(() => _status = '내보냈어: ${file.path}');
  }

  Future<void> _clearLocal() async {
    await _capture.clearAll();
    if (!mounted) return;
    RemineScope.maybeOf(context)?.refresh();
    setState(() {
      _records = const [];
      _status = '폰에 저장된 OCR 결과를 지웠어.';
    });
  }

  /// 이 앨범 전체의 파일명 앱 이름별 장수(앱 이름과 개수만 — OCR은 하지 않는다).
  Future<void> _showAppCounts() async {
    final id = _albumId;
    if (id == null) return;
    setState(() => _status = '앨범 전체 파일명을 읽는 중…');
    final photos = await _capture.all(id);
    if (!mounted) return;
    setState(() => _status = '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) =>
          _AppCountSheet(total: photos.length, counts: countByApp(photos)),
    );
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _photos.length) {
        _selected.clear();
      } else {
        _selected.addAll(_photos.map((p) => p.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false, // 아래 시스템 영역은 하단 패널 배경이 채운다
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                4,
                AppSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  const BackButtonCircle(),
                  Expanded(
                    child: Text(
                      'OCR 측정 (디버그)',
                      style: AppText.sectionTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.services.remote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.s8,
                  AppSpacing.screenPadding,
                  0,
                ),
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    PressableScale(
                      onTap: _syncNow,
                      child: AppChip.outlined(label: '지금 동기화'),
                    ),
                    PressableScale(
                      onTap: _sendTestPush,
                      child: AppChip.outlined(label: '테스트 알림 보내기'),
                    ),
                  ],
                ),
              ),
            if (_deviceIdLine.isNotEmpty)
              GestureDetector(
                onLongPress: _copyDeviceId, // 길게 누르면 복사
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.s4,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: Text(
                    _deviceIdLine,
                    style: AppText.caption.copyWith(color: AppColors.inkSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.s8,
              ),
              child: Row(
                children: [
                  for (final a in _albums) ...[
                    PressableScale(
                      key: ValueKey('album-${a.id}'),
                      onTap: _running ? null : () => _selectAlbum(a.id),
                      child: a.id == _albumId
                          ? AppChip.selected(label: _albumLabel(a))
                          : AppChip.outlined(label: _albumLabel(a)),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                  ],
                ],
              ),
            ),
            Expanded(child: _grid()),
            _bottomPanel(),
          ],
        ),
      ),
    );
  }

  /// 이름이 같은 앨범은 경로를 붙여 구분한다(자동으로 합치지 않고, 여기서 직접 고른다).
  String _albumLabel(GalleryAlbum a) {
    final dup = _albums.where((x) => x.name == a.name).length > 1;
    final path = a.relativePath;
    return dup && path != null
        ? '${a.name} ${a.count} · $path'
        : '${a.name} ${a.count}';
  }

  Widget _grid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Text(
            _status.isEmpty ? '이 앨범엔 사진이 없어.' : _status,
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, i) {
        final p = _photos[i];
        final on = _selected.contains(p.id);
        return GestureDetector(
          key: ValueKey('photo-${p.id}'),
          onTap: _running
              ? null
              : () => setState(
                  () => on ? _selected.remove(p.id) : _selected.add(p.id),
                ),
          child: SelectableThumb(
            selected: on,
            child: GalleryThumb(reader: widget.services.reader, photoId: p.id),
          ),
        );
      },
    );
  }

  Widget _bottomPanel() {
    final canRun = !_running && _selected.isNotEmpty;
    // 아주 작은 화면에서도 격자가 밀려나지 않게, 아래 패널은 화면의 40%까지만 쓰고 넘치면 스크롤한다.
    // 배경은 화면 전체 폭 + 하단 시스템 영역까지 채우고(SizedBox 가로 최대), 안쪽 여백은 내용에만 준다.
    return SizedBox(
      width: double.infinity,
      child: Material(
        key: const ValueKey('bottom-panel'),
        color: AppColors.chip,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_running) ...[
                    // 진행 숫자는 제목급으로, 멈추기는 같은 줄 오른쪽 끝(글자가 길면 숫자가 줄어든다).
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '처리 중 $_done / ${_selected.length}',
                            style: AppText.sectionTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        AppButton(label: '멈추기', onTap: () => _cancel = true),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: LinearProgressIndicator(
                        key: const ValueKey('ocr-progress'),
                        value: _selected.isEmpty ? 0 : _done / _selected.length,
                        minHeight: 8,
                        backgroundColor: AppColors.border,
                        color: AppColors.celadonDeep,
                      ),
                    ),
                  ] else
                    Text(
                      '${_selected.length}장 선택 · 최근 ${DeviceCaptureService.maxPhotos}장까지',
                      style: AppText.label,
                    ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(_status, style: AppText.caption),
                  ],
                  if (!_running) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        ...[
                          AppButton(
                            label: _selected.length == _photos.length
                                ? '선택 해제'
                                : '전체 선택',
                            onTap: _photos.isEmpty ? null : _toggleAll,
                            outlined: true,
                          ),
                          AppButton(
                            label: 'OCR 실행',
                            onTap: canRun ? _run : null,
                          ),
                          AppButton(
                            label: 'JSON 내보내기',
                            onTap: _records.isEmpty ? null : _export,
                            outlined: true,
                          ),
                          AppButton(
                            label: '앱 이름별 개수',
                            onTap: _albumId == null ? null : _showAppCounts,
                            outlined: true,
                          ),
                          AppButton(
                            label: '저장된 결과 지우기',
                            onTap: _clearLocal,
                            outlined: true,
                          ),
                          // 테스트용 초기화(이 화면 자체가 디버그 빌드 전용)
                          AppButton(
                            label: '튜토리얼 다시 보기',
                            onTap: _resetTutorial,
                            outlined: true,
                          ),
                          AppButton(
                            label: '첫 실행 안내 다시 보기',
                            onTap: _resetFirstRun,
                            outlined: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _kindLabel(AppCount c) => switch (c.kind) {
  AppKind.messenger => '메신저 → 대화',
  AppKind.financial => '금융 → 기타·숨김',
  AppKind.privateApp => '통화·연락처 → 기타·숨김',
  null => c.name == null ? '앱 이름 없음' : '목록에 없음',
};

/// "파일명 앱 이름별 개수". 목록에 없음으로 나온 이름이 `app_rules.dart`에 추가할 후보다.
class _AppCountSheet extends StatelessWidget {
  const _AppCountSheet({required this.total, required this.counts});

  final int total;
  final List<AppCount> counts;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.s20,
                AppSpacing.screenPadding,
                AppSpacing.s8,
              ),
              child: Text('앱 이름별 개수 · 전체 $total장', style: AppText.sectionTitle),
            ),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                  vertical: AppSpacing.s8,
                ),
                itemCount: counts.length,
                itemBuilder: (_, i) {
                  final c = counts[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            c.name ?? '(앱 이름 없음)',
                            style: AppText.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Flexible(
                          child: Text(
                            '${c.count}장 · ${_kindLabel(c)}',
                            style: AppText.caption,
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
