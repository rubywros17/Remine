import 'dart:async' show scheduleMicrotask;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../data/device/gallery_reader.dart';
import '../models/screenshot_item.dart';
import 'capture_thumb.dart';

/// 열린 미리 보기를 닫는 손잡이.
class PeekHandle {
  PeekHandle._(this._open);

  final ValueNotifier<bool> _open;

  void close() => _open.value = false;
}

/// 꾹 눌러 크게 보기(인스타그램 그리드 미리 보기 방식). [from](썸네일의 화면 좌표)에서 화면 가운데로 커진다.
/// 손을 떼면 [PeekHandle.close]로 줄어들며 닫힌다. 누르는 순간 가벼운 햅틱.
///
/// [Flutter 메모] Overlay는 화면 맨 위에 위젯을 잠깐 띄우는 층이다(라우트를 쌓지 않아 그리드 상태가 그대로다).
PeekHandle showPeek(BuildContext context, ScreenshotItem item, Rect from) {
  HapticFeedback.mediumImpact();
  final open = ValueNotifier(true);
  final reader = DeviceScope.maybeOf(context)?.reader;
  // 맨 위 Overlay는 화면 쪽 MediaQuery 밖일 수 있어, "애니메이션 줄이기"는 누른 자리에서 읽어 넘긴다.
  final reduced = AppMotion.reduced(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => PeekPreview(
      item: item,
      from: from,
      open: open,
      reader: reader,
      reduced: reduced,
      onClosed: () {
        entry.remove();
        // close()가 알리는 도중에 불릴 수 있어(애니메이션 줄이기) 정리는 알림이 끝난 뒤에.
        scheduleMicrotask(open.dispose);
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return PeekHandle._(open);
}

/// 미리 보기 한 장: 블러 + 검정 40% 배경 위에 원래 비율 그대로(좌우 여백 20, 모서리 22), 아래에 촬영 시각·출처 앱.
/// 썸네일을 먼저 크게 보여 주고 원본 해상도가 오면 바꿔 끼운다.
class PeekPreview extends StatefulWidget {
  const PeekPreview({
    super.key,
    required this.item,
    required this.from,
    required this.open,
    required this.reader,
    required this.reduced,
    required this.onClosed,
  });

  final ScreenshotItem item;
  final Rect from;
  final ValueListenable<bool> open;
  final GalleryReader? reader;

  /// "애니메이션 줄이기": 커지고 줄어드는 효과 없이 바로 열고 닫는다.
  final bool reduced;
  final VoidCallback onClosed;

  @override
  State<PeekPreview> createState() => _PeekPreviewState();
}

class _PeekPreviewState extends State<PeekPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: AppPeek.open,
    reverseDuration: AppPeek.close,
  );
  double? _aspect;
  Future<Uint8List?>? _original;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_onOpenChanged);
    _original = widget.reader?.bytes(widget.item.localAssetId);
    _prepare();
  }

  /// 비율을 먼저 안다(잘리지 않게 상자 크기를 정하려고). 모르면 세로 화면 비율.
  Future<void> _prepare() async {
    final aspect = await widget.reader?.aspectRatio(widget.item.localAssetId);
    if (!mounted) return;
    setState(() => _aspect = aspect ?? AppPeek.fallbackAspect);
    if (!widget.open.value) {
      widget.onClosed(); // 비율을 읽는 사이에 손을 뗐다
      return;
    }
    _started = true;
    if (widget.reduced) {
      _t.value = 1; // 커지는 효과 없이 바로
    } else {
      _t.forward();
    }
  }

  void _onOpenChanged() {
    if (widget.open.value || !_started) return;
    if (widget.reduced) {
      widget.onClosed();
    } else {
      _t.reverse().whenComplete(widget.onClosed);
    }
  }

  @override
  void dispose() {
    widget.open.removeListener(_onOpenChanged);
    _t.dispose();
    super.dispose();
  }

  /// 화면 가운데의 최종 자리: 좌우 여백 20, 위아래(+아래 글자 줄) 잘림 없이 원래 비율.
  Rect _target(Size screen, EdgeInsets safe, double aspect) {
    const side = AppPeek.sidePadding;
    const caption = AppPeek.captionGap + AppPeek.captionHeight;
    final maxW = screen.width - side * 2;
    final maxH = screen.height - safe.vertical - side * 2 - caption;
    var w = maxW;
    var h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    final centerY = safe.top + (screen.height - safe.vertical - caption) / 2;
    return Rect.fromCenter(
      center: Offset(screen.width / 2, centerY),
      width: w,
      height: h,
    );
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    final to = _target(screen, MediaQuery.paddingOf(context), aspect);
    final item = widget.item;
    final app = item.sourceApp;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, image) {
          final t = AppPeek.curve.transform(_t.value);
          final rect = Rect.lerp(widget.from, to, t)!;
          // Overlay에는 Material이 없어 글자 기본 스타일(노란 밑줄 경고)이 빠진다 → 투명 Material로 감싼다.
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: AppPeek.blur * t,
                      sigmaY: AppPeek.blur * t,
                    ),
                    child: ColoredBox(
                      color: AppPeek.scrim.withValues(
                        alpha: AppPeek.scrim.a * t,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppPeek.thumbRadius +
                          (AppPeek.radius - AppPeek.thumbRadius) * t,
                    ),
                    child: image,
                  ),
                ),
                Positioned(
                  left: AppPeek.sidePadding,
                  right: AppPeek.sidePadding,
                  top: rect.bottom + AppPeek.captionGap,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Text(
                      [
                        formatStamp(item.takenAt),
                        if (app != null) sourceAppLabel(app),
                      ].join('  ·  '),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 원본이 오기 전까지는 같은 비율의 썸네일을 크게.
            CaptureThumb(
              assetId: item.localAssetId,
              seed: item.id,
              radius: 0,
              size: 480,
              aspect: aspect,
            ),
            FutureBuilder<Uint8List?>(
              future: _original,
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) return const SizedBox.shrink();
                return Image.memory(
                  data,
                  key: const ValueKey('peek-original'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
