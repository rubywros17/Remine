import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/gallery_reader.dart';
import 'thumb_placeholder.dart';

/// 캡처 한 장의 썸네일. 기기 모드에서는 asset id로 **기기 사진**을 읽어 보여 주고, 가짜 데이터 모드(크롬·테스트)에서는
/// 예전처럼 색 블록([ThumbPlaceholder])을 보여 준다.
///
/// - 불러오는 동안은 색 블록, 기기에서 사진이 지워졌거나 읽을 수 없으면 "사진이 없어요" 자리 표시.
/// - 서버에는 이미지가 없으므로(저장하지 않는다) 썸네일은 항상 기기 갤러리에서 온다.
/// - [child]는 날짜 배지처럼 위에 올릴 것(사진 위에도 그대로 올라간다).
class CaptureThumb extends StatefulWidget {
  const CaptureThumb({
    super.key,
    required this.assetId,
    required this.seed,
    this.radius = AppRadii.card,
    this.size = 360,
    this.aspect,
    this.child,
  });

  final String assetId;

  /// 사진이 없을 때·가짜 모드에서 색을 고르는 값(캡처 id).
  final int seed;
  final double radius;

  /// 요청할 썸네일 한 변(px). 클수록 선명하지만 무겁다.
  final int size;

  /// 사진의 폭/높이 비율. 주면 그 비율대로 썸네일을 받아(정사각 크롭 없이) 카드에 사진 전체가 보인다.
  final double? aspect;
  final Widget? child;

  @override
  State<CaptureThumb> createState() => _CaptureThumbState();
}

class _CaptureThumbState extends State<CaptureThumb> {
  GalleryReader? _reader;
  Future<Uint8List?>? _bytes;
  String? _loadedFor;
  double? _loadedAspect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reader = DeviceScope.maybeOf(context)?.reader;
    _load();
  }

  @override
  void didUpdateWidget(CaptureThumb old) {
    super.didUpdateWidget(old);
    _load();
  }

  // 같은 asset이면 다시 읽지 않는다(스크롤·Hero 전환 중에 깜빡이지 않게 Future를 State에 붙들어 둔다).
  void _load() {
    final reader = _reader;
    if (reader == null) {
      _bytes = null;
      _loadedFor = null;
    } else if (_loadedFor != widget.assetId || _loadedAspect != widget.aspect) {
      _loadedFor = widget.assetId;
      _loadedAspect = widget.aspect;
      final aspect = widget.aspect;
      _bytes = reader.thumbnail(
        widget.assetId,
        size: widget.size,
        height: aspect == null ? null : (widget.size / aspect).round(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return ThumbPlaceholder(
        seed: widget.seed,
        radius: widget.radius,
        child: widget.child,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return ThumbPlaceholder(
            seed: widget.seed,
            radius: widget.radius,
            child: widget.child,
          );
        }
        final data = snap.data;
        if (data == null || snap.hasError) {
          return NoPhotoPlaceholder(radius: widget.radius, child: widget.child);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                data,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // 디코딩 실패(깨진 썸네일)도 같은 자리 표시로 처리한다.
                errorBuilder: (_, _, _) => NoPhotoPlaceholder(
                  radius: widget.radius,
                  child: widget.child,
                ),
              ),
              ?widget.child,
            ],
          ),
        );
      },
    );
  }
}

/// 기기에서 사진이 지워졌을 때의 자리 표시. 좁은 칸에서도 넘치지 않게 글자는 줄어들거나 숨는다.
class NoPhotoPlaceholder extends StatelessWidget {
  const NoPhotoPlaceholder({
    super.key,
    this.radius = AppRadii.card,
    this.child,
  });

  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '사진이 없어요',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.chip,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.imageOff,
                          size: 24,
                          color: AppColors.inkSub,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          '사진이 없어요',
                          style: AppText.caption.copyWith(
                            color: AppColors.inkSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}
