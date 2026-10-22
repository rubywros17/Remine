import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/thumb_placeholder.dart';

/// 상세 이미지 카드를 누르면 열리는 전체 화면 보기.
///
/// - 두 손가락으로 확대·축소(1배~5배), 확대한 뒤에는 한 손가락으로 움직인다([InteractiveViewer]).
/// - 닫기: 왼쪽 위 X 버튼, 또는 확대하지 않은 상태에서 **아래로 쓸기**(확대 중에는 쓸어서 닫히지 않는다).
/// - 사진은 기기 갤러리의 원본이다(서버에는 이미지가 없다). 지워졌으면 "사진이 없어요".
///   가짜 데이터 모드(크롬·테스트)에서는 색 블록을 보여 준다.
///
/// [Flutter 메모] InteractiveViewer는 핀치 확대·이동을 해 주는 내장 위젯이다. 확대하지 않았을 때는 이동을 꺼 두어
/// 아래로 쓸기(닫기)와 제스처가 겹치지 않게 했다.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.assetId,
    required this.seed,
  });

  final String assetId;
  final int seed;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  static const _maxScale = 5.0;

  /// 이 거리(px) 이상 쓸거나, 이 속도(px/s) 이상으로 쓸면 닫는다.
  static const _closeDistance = 120.0;
  static const _closeVelocity = 800.0;

  final TransformationController _transform = TransformationController();
  Future<Uint8List?>? _bytes;
  bool _zoomed = false;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reader = DeviceScope.maybeOf(context)?.reader;
    _bytes ??= reader?.bytes(widget.assetId);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final fade = (1 - (_dragDy.abs() / 400)).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 확대 중에는 InteractiveViewer가 이동을 맡는다.
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(
                    () => _dragDy = (_dragDy + d.delta.dy).clamp(0, 1000),
                  ),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_dragDy >= _closeDistance ||
                        (d.primaryVelocity ?? 0) >= _closeVelocity) {
                      _close();
                    } else {
                      setState(() => _dragDy = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragDy),
              child: InteractiveViewer(
                key: const ValueKey('photo-viewer'),
                transformationController: _transform,
                minScale: 1,
                maxScale: _maxScale,
                panEnabled: _zoomed,
                child: SizedBox.expand(child: Center(child: _photo())),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: Semantics(
                  button: true,
                  label: '닫기',
                  excludeSemantics: true,
                  onTap: _close,
                  child: GestureDetector(
                    key: const ValueKey('photo-viewer-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              LucideIcons.x,
                              size: 22,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo() {
    final bytes = _bytes;
    if (bytes == null) {
      // 가짜 데이터 모드: 사진이 없으니 카드 비율의 색 블록.
      return AspectRatio(
        aspectRatio: 0.62,
        child: ThumbPlaceholder(seed: widget.seed),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final data = snap.data;
        if (data == null || snap.hasError) {
          return const SizedBox(
            width: 220,
            height: 220,
            child: NoPhotoPlaceholder(),
          );
        }
        return Image.memory(
          data,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 220,
            height: 220,
            child: NoPhotoPlaceholder(),
          ),
        );
      },
    );
  }
}
