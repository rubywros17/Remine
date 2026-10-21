import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../device/gallery_reader.dart';
import 'jpeg_guard.dart';

/// 원본 이미지를 줄여 JPEG로 다시 인코딩한다. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class ImageShrinker {
  /// 긴 변이 [maxLongSide] 이하가 되게 줄인 JPEG. 실패하면 null.
  Future<Uint8List?> shrink(
    Uint8List original, {
    required int maxLongSide,
    required int quality,
  });
}

/// `flutter_image_compress`(안드로이드 네이티브)로 줄인다. **`keepExif: false`** — EXIF·GPS를 넣지 않는다.
class FlutterImageShrinker implements ImageShrinker {
  const FlutterImageShrinker();

  @override
  Future<Uint8List?> shrink(
    Uint8List original, {
    required int maxLongSide,
    required int quality,
  }) async {
    // 크기만 읽는다(전체 디코딩 없음). 이 라이브러리의 minWidth/minHeight는 "둘 다 이 값 이상으로 줄인다"는 뜻이라
    // 세로로 긴 스크린샷에서 긴 변이 안 줄어든다 → 목표 가로·세로를 직접 계산해 넘긴다.
    final buffer = await ui.ImmutableBuffer.fromUint8List(original);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      buffer.dispose();
      return null;
    }
    final w = descriptor.width;
    final h = descriptor.height;
    descriptor.dispose();
    buffer.dispose();
    final scale = maxLongSide / (w > h ? w : h);
    final targetW = scale >= 1 ? w : (w * scale).round().clamp(1, w);
    final targetH = scale >= 1 ? h : (h * scale).round().clamp(1, h);
    return FlutterImageCompress.compressWithList(
      original,
      minWidth: targetW,
      minHeight: targetH,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }
}

/// 서버 상한(`/api/config`) 안에 들어오는 분석용 JPEG를 만든다.
/// 단계(긴 변 배율, 품질)를 내려가며 `imageMaxBytes` 이하가 될 때까지 줄이고, 끝까지 안 되면 null(이미지 없이 보낸다).
class ImagePreparer {
  ImagePreparer(this._reader, this._shrinker);

  final GalleryReader _reader;
  final ImageShrinker _shrinker;

  /// (긴 변 배율, JPEG 품질). `IMAGE_TOO_LARGE`로 돌아오면 [minLevel]을 올려 더 줄인다.
  static const levels = [(1.0, 85), (1.0, 70), (0.75, 60), (0.5, 50)];

  Future<Uint8List?> prepare(
    String assetId, {
    required int maxLongSide,
    required int maxBytes,
    int minLevel = 0,
  }) async {
    final original = await _reader.bytes(assetId);
    if (original == null) return null;
    for (var level = minLevel; level < levels.length; level++) {
      final (ratio, quality) = levels[level];
      final shrunk = await _shrinker.shrink(
        original,
        maxLongSide: (maxLongSide * ratio).round(),
        quality: quality,
      );
      if (shrunk == null) return null;
      // 라이브러리 동작에 기대지 않고 메타데이터 세그먼트를 한 번 더 지운다. JPEG이 아니면 보내지 않는다.
      final clean = stripJpegMetadata(shrunk);
      if (clean == null) return null;
      if (clean.length <= maxBytes) return clean;
    }
    return null;
  }

  static int get lastLevel => levels.length - 1;
}
