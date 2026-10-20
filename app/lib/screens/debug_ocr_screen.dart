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
                      key: ValueKey('album-${a.name}'),
                      onTap: _running ? null : () => _selectAlbum(a.id),
                      child: a.id == _albumId
                          ? AppChip.selected(label: '${a.name} ${a.count}')
                          : AppChip.outlined(label: '${a.name} ${a.count}'),
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
    return Material(
      color: AppColors.chip,
      child: Padding(
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

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
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
          if (widget.selected)
            ColoredBox(color: AppColors.lemon.withValues(alpha: 0.4)),
          if (widget.selected)
            const Positioned(
              top: 6,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    LucideIcons.check,
                    size: 14,
                    color: AppColors.lemon,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
