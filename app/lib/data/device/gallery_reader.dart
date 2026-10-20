import 'dart:typed_data';

/// 사진 접근 권한 상태. Android 14의 "일부만 허용"이 [limited]다.
enum GalleryAccess { authorized, limited, denied }

class GalleryAlbum {
  const GalleryAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.isScreenshots = false,
  });

  final String id;
  final String name;
  final int count;

  /// 기본 대상(Screenshots 앨범)인지.
  final bool isScreenshots;
}

class GalleryPhoto {
  const GalleryPhoto({
    required this.id,
    required this.fileName,
    required this.takenAt,
    required this.modifiedAt,
  });

  final String id;
  final String fileName;
  final DateTime takenAt;

  /// 사진이 바뀌었는지 보는 값(epoch 초). OCR 캐시 키의 일부.
  final int modifiedAt;
}

/// 기기 갤러리를 읽는 경계. 구현은 photo_manager, 테스트는 Fake로 바꿔 끼운다.
/// 이미지는 기기 밖으로 나가지 않는다 — 여기서 나온 바이트는 기기 안 OCR에만 쓴다.
abstract interface class GalleryReader {
  /// [request]가 true면 권한 팝업을 띄운다.
  Future<GalleryAccess> access({bool request = false});

  /// "일부만 허용"에서 사진을 다시 고르는 시스템 선택창.
  Future<void> reselect();

  Future<void> openSettings();

  /// 이미지 앨범 목록. Screenshots 앨범이 있으면 맨 앞.
  Future<List<GalleryAlbum>> albums();

  /// 최신순 최대 [limit]장.
  Future<List<GalleryPhoto>> recent(String albumId, {int limit = 300});

  Future<Uint8List?> thumbnail(String photoId, {int size = 220});

  /// OCR 입력용 원본 바이트.
  Future<Uint8List?> bytes(String photoId);
}
