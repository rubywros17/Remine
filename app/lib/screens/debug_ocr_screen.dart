import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/device/device_capture_service.dart';
import '../data/device/device_services.dart';
import '../data/device/gallery_reader.dart';
import '../data/device/ocr_export.dart';
import '../data/device/ocr_store.dart';
import '../widgets/app_button.dart';
import '../widgets/pressable_scale.dart';
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

  @override
  void initState() {
    super.initState();
    _loadAlbums();
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
    setState(() {
      _running = false;
      _records = run.records;
      _status =
          '${run.records.length}장 완료 · 이전 결과 재사용 ${run.skipped}장 · 실패 ${run.failed}장';
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
    await _capture.store.clear();
    if (!mounted) return;
    setState(() {
      _records = const [];
      _status = '폰에 저장된 OCR 결과를 지웠어.';
    });
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
          child: _Thumb(
            reader: widget.services.reader,
            photoId: p.id,
            selected: on,
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
                  Text(
                    _running
                        ? '처리 중 $_done / ${_selected.length}'
                        : '${_selected.length}장 선택 · 최근 ${DeviceCaptureService.maxPhotos}장까지',
                    style: AppText.label,
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(_status, style: AppText.caption),
                  ],
                  const SizedBox(height: AppSpacing.s12),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: [
                      if (_running)
                        AppButton(label: '멈추기', onTap: () => _cancel = true)
                      else ...[
                        AppButton(
                          label: _selected.length == _photos.length
                              ? '선택 해제'
                              : '전체 선택',
                          onTap: _photos.isEmpty ? null : _toggleAll,
                          outlined: true,
                        ),
                        AppButton(label: 'OCR 실행', onTap: canRun ? _run : null),
                        AppButton(
                          label: 'JSON 내보내기',
                          onTap: _records.isEmpty ? null : _export,
                          outlined: true,
                        ),
                        AppButton(
                          label: '저장된 결과 지우기',
                          onTap: _clearLocal,
                          outlined: true,
                        ),
                      ],
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

class _Thumb extends StatefulWidget {
  const _Thumb({
    required this.reader,
    required this.photoId,
    required this.selected,
  });

  final GalleryReader reader;
  final String photoId;
  final bool selected;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<Uint8List?> _bytes = widget.reader.thumbnail(
    widget.photoId,
  );

  static const _radius = 12.0;
  static const _circle = 22.0;
  static const _corner = 6.0;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // 애니메이션 줄이기면 duration이 0이라 축소가 즉시 적용된다.
    final duration = AppMotion.duration(context, MotionDuration.fast);
    return LayoutBuilder(
      builder: (context, box) {
        // 축소된 사진의 모서리에 체크 원을 맞추기 위한 한쪽 여백.
        final inset = selected
            ? box.maxWidth * (1 - AppGesture.selectedPhotoScale) / 2
            : 0.0;
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedScale(
                scale: selected ? AppGesture.selectedPhotoScale : 1.0,
                duration: duration,
                curve: AppMotion.standard,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: AppColors.chip,
                        child: FutureBuilder<Uint8List?>(
                          future: _bytes,
                          builder: (context, snap) => snap.data == null
                              ? const SizedBox.shrink()
                              : Image.memory(snap.data!, fit: BoxFit.cover),
                        ),
                      ),
                      if (selected)
                        const ColoredBox(color: AppColors.selectionDim),
                    ],
                  ),
                ),
              ),
            ),
            // 우상단 원: 선택 = 검은 원 + 레몬 체크(축소된 사진 모서리에 맞춤), 미선택 = 흰 테두리 빈 원 + 얇은 그림자
            AnimatedPositioned(
              duration: duration,
              curve: AppMotion.standard,
              top: _corner + inset,
              right: _corner + inset,
              child: selected
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: _circle,
                        height: _circle,
                        child: Icon(
                          LucideIcons.check,
                          size: 14,
                          color: AppColors.lemon,
                        ),
                      ),
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: AppColors.white, width: 2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.selectionRingShadow,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: SizedBox(width: _circle, height: _circle),
                    ),
            ),
          ],
        );
      },
    );
  }
}
