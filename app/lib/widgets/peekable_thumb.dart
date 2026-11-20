import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/screenshot_item.dart';
import 'peek_preview.dart';

/// 그리드 한 칸의 손가락 처리: 탭은 [onTap](선택/해제), 꾹 누르면 크게 보기([showPeek], 손 떼면 닫힘).
/// 꾹 누르는 동안엔 선택이 바뀌지 않는다. 정리 묶음 화면과 분석 제외 화면이 같이 쓴다.
///
/// [Flutter 메모] 길게 누르기는 [AppTidy.peekPress](0.3초)가 지나야 이긴다. 그 전에 손가락이 움직이면 스크롤이
/// 이겨서 서로 겹치지 않는다. GestureDetector는 이 시간을 못 바꿔서 RawGestureDetector로 인식기를 직접 단다.
/// Listener는 경쟁에 끼지 않고 손가락이 닿는 순간만 알려 준다(미리 디코딩 시작).
class PeekableThumb extends StatefulWidget {
  const PeekableThumb({
    super.key,
    required this.item,
    required this.onTap,
    required this.child,
  });

  /// 미리 보기에 띄울 캡처(사진은 [ScreenshotItem.localAssetId]로 읽는다).
  final ScreenshotItem item;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<PeekableThumb> createState() => _PeekableThumbState();
}

class _PeekableThumbState extends State<PeekableThumb> {
  final _box = GlobalKey();
  PeekHandle? _peek;

  /// 손가락이 닿는 순간 디코딩을 시작한 이미지. 꾹 누름이 인식되면 이걸로 바로 띄운다(탭으로 끝나도 캐시에 남을 뿐).
  PeekImages? _warm;

  void _warmUp() => _warm ??= PeekImages.warm(context, widget.item);

  /// 썸네일 자리(화면 좌표)에서 미리 보기를 띄운다.
  void _open() {
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _close();
    _warmUp();
    _peek = showPeek(
      context,
      widget.item,
      box.localToGlobal(Offset.zero) & box.size,
      _warm!,
    );
  }

  void _close() {
    _peek?.close();
    _peek = null;
  }

  @override
  void didUpdateWidget(PeekableThumb old) {
    super.didUpdateWidget(old);
    if (old.item.localAssetId != widget.item.localAssetId) _warm = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _warmUp(),
    child: RawGestureDetector(
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) => r.onTap = widget.onTap,
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: AppTidy.peekPress),
              (r) => r
                ..onLongPressStart = ((_) => _open())
                ..onLongPressEnd = ((_) => _close())
                ..onLongPressCancel = _close,
            ),
      },
      child: KeyedSubtree(key: _box, child: widget.child),
    ),
  );
}
