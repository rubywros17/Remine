import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../data/device/device_services.dart';
import '../models/screenshot_item.dart';
import 'capture_thumb.dart';

/// 미리 보기에 쓸 이미지를 **손가락이 닿는 순간** 미리 디코딩해 둔다(꾹 누름이 인식될 때는 이미 준비돼 있게).
///
/// - [aspect]: 사진의 원래 비율(잘리지 않는 상자 크기를 정한다)
/// - [thumb]: 그 비율의 썸네일([AppTidy.peekThumbSize]). 확대 애니메이션 동안 이걸로 움직인다
/// - [original]: 원본 해상도. 화면 너비 × devicePixelRatio로 줄여 디코딩하고, 다 열린 뒤 크로스페이드로 바꿔 낀다
/// 가짜 데이터 모드(갤러리 없음)는 비율만 기본값이고 이미지는 없다(자리 표시 색).
class PeekImages {
  PeekImages._(this.aspect, this.thumb, this.original);

  factory PeekImages.warm(BuildContext context, ScreenshotItem item) {
    final reader = DeviceScope.maybeOf(context)?.reader;
    if (reader == null) {
      return PeekImages._(
        Future.value(AppTidy.peekFallbackAspect),
        Future.value(),
        Future.value(),
      );
    }
    final id = item.localAssetId;
    final config = createLocalImageConfiguration(context);
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final aspect = reader
        .aspectRatio(id)
        .then((a) => a ?? AppTidy.peekFallbackAspect);
    const size = AppTidy.peekThumbSize;
    return PeekImages._(
      aspect,
      aspect.then(
        (a) => _decode(
          reader.thumbnail(id, size: size, height: (size / a).round()),
          config,
        ),
      ),
      _decode(reader.bytes(id), config, width: cacheWidth),
    );
  }

  final Future<double> aspect;
  final Future<ImageProvider?> thumb;
  final Future<ImageProvider?> original;

  /// 바이트를 이미지 캐시에 디코딩해 둔다. 못 읽거나 깨진 이미지면 null.
  static Future<ImageProvider?> _decode(
    Future<Uint8List?> bytes,
    ImageConfiguration config, {
    int? width,
  }) async {
    final data = await bytes;
    if (data == null) return null;
    final ImageProvider provider = width == null
        ? MemoryImage(data)
        : ResizeImage(MemoryImage(data), width: width);
    final done = Completer<bool>();
    final stream = provider.resolve(config);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete(true);
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete(false);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return await done.future ? provider : null;
  }
}

/// 열린 미리 보기를 닫는 손잡이.
class PeekHandle {
  PeekHandle._(this._open);

  final ValueNotifier<bool> _open;

  void close() => _open.value = false;
}

/// 꾹 눌러 크게 보기(인스타그램 그리드 미리 보기 방식). [from](썸네일의 화면 좌표)에서 화면 가운데로 커진다.
/// 손을 떼면 [PeekHandle.close]로 썸네일 자리로 되돌아가며 닫힌다. 꾹 누름이 인식되는 순간 가벼운 햅틱.
///
/// [Flutter 메모] Overlay는 화면 맨 위에 위젯을 잠깐 띄우는 층이다(라우트를 쌓지 않아 그리드 상태가 그대로다).
PeekHandle showPeek(
  BuildContext context,
  ScreenshotItem item,
  Rect from,
  PeekImages images,
) {
  HapticFeedback.mediumImpact();
  final open = ValueNotifier(true);
  // 맨 위 Overlay는 화면 쪽 MediaQuery 밖일 수 있어, "애니메이션 줄이기"는 누른 자리에서 읽어 넘긴다.
  final reduced = AppMotion.reduced(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => PeekPreview(
      item: item,
      from: from,
      open: open,
      images: images,
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
///
/// 매끄럽게 움직이려고:
/// - 사진 상자는 처음부터 **최종 크기**이고, 썸네일 자리·크기에서 시작하는 Transform(이동+배율)만 움직인다(레이아웃 없음)
/// - 배경 블러 세기는 고정, 그 층의 투명도만 0→1
/// - 사진·배경은 각각 RepaintBoundary라 매 프레임 다시 그리지 않고 합성만 한다
/// - 원본은 다 열린 뒤 [AppTidy.peekCrossfade] 동안 썸네일 위로 겹쳐 나타난다
class PeekPreview extends StatefulWidget {
  const PeekPreview({
    super.key,
    required this.item,
    required this.from,
    required this.open,
    required this.images,
    required this.reduced,
    required this.onClosed,
  });

  final ScreenshotItem item;
  final Rect from;
  final ValueListenable<bool> open;
  final PeekImages images;

  /// "애니메이션 줄이기": 커지고 줄어드는 효과 없이 바로 열고 닫는다.
  final bool reduced;
  final VoidCallback onClosed;

  @override
  State<PeekPreview> createState() => _PeekPreviewState();
}

class _PeekPreviewState extends State<PeekPreview>
    with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: AppTidy.peekOpen,
    reverseDuration: AppTidy.peekClose,
  );

  /// 닫을 때의 곡선은 "열린 상태 → 썸네일 자리" 진행에 맞춘 것이라 뒤집어서 쓴다.
  late final Animation<double> _move = CurvedAnimation(
    parent: _t,
    curve: AppTidy.peekOpenCurve,
    reverseCurve: const FlippedCurve(AppTidy.peekCloseCurve),
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.reduced ? Duration.zero : AppTidy.peekCrossfade,
  );
  double? _aspect;
  ImageProvider? _thumb;
  ImageProvider? _original;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_onOpenChanged);
    _start();
  }

  Future<void> _start() async {
    final aspect = await widget.images.aspect;
    // 썸네일은 보통 이미 준비돼 있다. 잠깐 기다려 보고 늦으면 자리 표시로 시작한다(움직임을 미루지 않는다).
    final thumb = await widget.images.thumb.timeout(
      const Duration(milliseconds: 80),
      onTimeout: () => null,
    );
    if (!mounted) return;
    if (!widget.open.value) {
      widget.onClosed(); // 준비하는 사이에 손을 뗐다
      return;
    }
    setState(() {
      _aspect = aspect;
      _thumb = thumb;
    });
    _started = true;
    if (thumb == null) {
      widget.images.thumb.then((t) {
        if (mounted && t != null) setState(() => _thumb = t);
      });
    }
    if (widget.reduced) {
      _t.value = 1;
    } else {
      await _t.forward().orCancel.catchError((_) {});
    }
    // 다 열린 뒤 원본으로 바꿔 낀다(확대 중에는 디코딩·교체로 끊기지 않게).
    final original = await widget.images.original;
    if (!mounted || original == null || !widget.open.value) return;
    setState(() => _original = original);
    _fade.forward();
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
    _fade.dispose();
    super.dispose();
  }

  /// 화면 가운데의 최종 자리: 좌우 여백 20, 위아래(+아래 글자 줄) 잘림 없이 원래 비율.
  Rect _target(Size screen, EdgeInsets safe, double aspect) {
    const side = AppTidy.peekSidePadding;
    const caption = AppTidy.peekCaptionGap + AppTidy.peekCaptionHeight;
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

  /// t=0이면 썸네일 자리·폭, t=1이면 제자리(최종 상자 가운데 기준).
  Matrix4 _matrix(double t, Rect to) {
    final from = widget.from;
    final scale = from.width / to.width;
    final shift = (from.center - to.center) * (1 - t);
    final s = scale + (1 - scale) * t;
    return Matrix4.translationValues(shift.dx, shift.dy, 0)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null) return const SizedBox.shrink();
    final to = _target(
      MediaQuery.sizeOf(context),
      MediaQuery.paddingOf(context),
      aspect,
    );
    final item = widget.item;
    final app = item.sourceApp;
    final thumb = _thumb;
    final original = _original;
    return IgnorePointer(
      // Overlay에는 Material이 없어 글자 기본 스타일(노란 밑줄 경고)이 빠진다 → 투명 Material로 감싼다.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: _move,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: AppTidy.peekBlur,
                      sigmaY: AppTidy.peekBlur,
                    ),
                    child: const ColoredBox(color: AppTidy.peekScrim),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: to,
              child: MatrixTransition(
                animation: _move,
                onTransform: (t) => _matrix(t, to),
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTidy.peekRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb != null)
                          Image(
                            image: thumb,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        else
                          CaptureThumb(
                            assetId: item.localAssetId,
                            seed: item.id,
                            radius: 0,
                            size: AppTidy.peekThumbSize,
                            aspect: aspect,
                          ),
                        if (original != null)
                          FadeTransition(
                            opacity: _fade,
                            child: Image(
                              key: const ValueKey('peek-original'),
                              image: original,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppTidy.peekSidePadding,
              right: AppTidy.peekSidePadding,
              top: to.bottom + AppTidy.peekCaptionGap,
              child: FadeTransition(
                opacity: _move,
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
      ),
    );
  }
}
