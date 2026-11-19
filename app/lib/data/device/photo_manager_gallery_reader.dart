import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:photo_manager/photo_manager.dart';

import 'gallery_reader.dart';

/// [GalleryReader]의 실제 구현(photo_manager). 기기에서만 동작한다.
class PhotoManagerGalleryReader implements GalleryReader {
  static const _option = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  @override
  Future<GalleryAccess> access({bool request = false}) async {
    final state = request
        ? await PhotoManager.requestPermissionExtend(requestOption: _option)
        : await PhotoManager.getPermissionState(requestOption: _option);
    return switch (state) {
      PermissionState.authorized => GalleryAccess.authorized,
      PermissionState.limited => GalleryAccess.limited,
      _ => GalleryAccess.denied,
    };
  }

  @override
  Future<void> reselect() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<GalleryAlbum>> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: false,
    );
    final albums = <GalleryAlbum>[];
    for (final p in paths) {
      albums.add(
        GalleryAlbum(
          id: p.id,
          name: p.name,
          count: await p.assetCountAsync,
          relativePath: await p.relativePathAsync,
        ),
      );
    }
    return orderAlbums(albums);
  }

  @override
  Future<List<GalleryPhoto>> recent(String albumId, {int limit = 300}) async {
    final path = await _album(albumId);
    if (path == null) return [];
    return _photos(await path.getAssetListRange(start: 0, end: limit));
  }

  @override
  Future<int> count(String albumId, {DateTime? from, DateTime? before}) async {
    final path = await _album(
      albumId,
      min: from,
      // 조건은 포함이라 1ms 앞까지
      max: before?.subtract(const Duration(milliseconds: 1)),
    );
    return await path?.assetCountAsync ?? 0;
  }

  @override
  Future<List<GalleryPhoto>> since(String albumId, DateTime from) async {
    final path = await _album(albumId, min: from);
    final count = await path?.assetCountAsync ?? 0;
    if (path == null || count == 0) return [];
    return _photos(await path.getAssetListRange(start: 0, end: count));
  }

  @override
  Future<List<GalleryPhoto>> olderThan(
    String albumId,
    PhotoPosition? before, {
    DateTime? notBefore,
    required int limit,
  }) async {
    // 갤러리 조건은 초 단위라 커서와 같은 초의 사진도 함께 온다 → 여유분을 더 읽고 여기서 정확히 거른다.
    // ponytail: 같은 초에 _sameSecondSlack장 넘게 찍힌 경우는 다음 실행에서 이어진다(드묾).
    final path = await _album(
      albumId,
      min: notBefore,
      max: before?.time.add(const Duration(seconds: 1)),
    );
    if (path == null) return [];
    final photos = await _photos(
      await path.getAssetListRange(start: 0, end: limit + _sameSecondSlack),
    );
    sortNewestFirst(photos);
    return photos
        .where((p) => before == null || p.position.isOlderThan(before))
        .take(limit)
        .toList();
  }

  static const _sameSecondSlack = 20;

  /// 최신순(생성 시각 내림차순) 앨범. [min]·[max]가 있으면 그 생성 시각 사이만. 조건에 맞는 사진이 없으면 null.
  ///
  /// photo_manager 주의(3.12):
  /// - `AssetPathEntity.fromId`는 생성 시각 상한을 늘 "지금"으로 덮어쓴다 → 커서 상한([max])이 무시돼 예전 스크린샷이
  ///   맨 앞 쪽만 되풀이해 읽힌다. 상한을 줄 때는 덮어쓰지 않게 `maxDateTimeToNow: false`로 직접 부른다.
  /// - 조건에 맞는 사진이 0장이면 결과 대신 `StateError('Unable to fetch properties for path …')`를 던진다
  ///   (예: 기기 등록 뒤 새 스크린샷이 아직 없을 때의 [since]). 이건 오류가 아니라 빈 결과다.
  Future<AssetPathEntity?> _album(
    String albumId, {
    DateTime? min,
    DateTime? max,
  }) async {
    final filter = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      createTimeCond: min == null && max == null
          ? DateTimeCond.def()
          : DateTimeCond(
              min: min ?? DateTime.fromMillisecondsSinceEpoch(0),
              max: max ?? DateTime(2100),
            ),
    );
    try {
      return await AssetPathEntity.obtainPathFromProperties(
        id: albumId,
        type: RequestType.image,
        optionGroup: filter,
        maxDateTimeToNow: max == null,
      );
    } on StateError {
      return null;
    }
  }

  Future<List<GalleryPhoto>> _photos(List<AssetEntity> assets) async {
    final photos = <GalleryPhoto>[];
    for (final a in assets) {
      final fileName = await a.titleAsync;
      final modified = a.modifiedDateSecond ?? 0;
      photos.add(
        GalleryPhoto(
          id: a.id,
          fileName: fileName,
          takenAt: resolveTakenAt(
            created: a.createDateTime,
            fileName: fileName,
            modifiedAtSeconds: modified,
          ),
          modifiedAt: modified,
          created: a.createDateTime,
        ),
      );
    }
    return photos;
  }

  @override
  Future<Uint8List?> thumbnail(
    String photoId, {
    int size = 220,
    int? height,
  }) async {
    final a = await AssetEntity.fromId(photoId);
    return a?.thumbnailDataWithSize(
      height == null ? ThumbnailSize.square(size) : ThumbnailSize(size, height),
    );
  }

  @override
  Future<double?> aspectRatio(String photoId) async {
    final a = await AssetEntity.fromId(photoId);
    if (a == null || a.orientatedWidth <= 0 || a.orientatedHeight <= 0) {
      return null;
    }
    return a.orientatedWidth / a.orientatedHeight;
  }

  @override
  Future<String?> fileName(String photoId) async =>
      (await AssetEntity.fromId(photoId))?.title;

  @override
  Future<Uint8List?> bytes(String photoId) async {
    final a = await AssetEntity.fromId(photoId);
    return a?.originBytes;
  }

  @override
  Future<Map<String, int>> fileSizes(List<String> photoIds) async {
    final sizes = <String, int>{};
    for (final id in photoIds) {
      try {
        final file = await (await AssetEntity.fromId(id))?.originFile;
        if (file != null) sizes[id] = await file.length();
      } catch (_) {
        // 못 읽은 장은 뺀다(합이 모자라면 화면이 용량 줄을 숨긴다).
      }
    }
    return sizes;
  }

  static const _trashMinSdk = 30; // MediaStore.createTrashRequest

  @override
  Future<bool> canMoveToTrash() async {
    try {
      final sdk = await const MethodChannel('remine/settings')
          .invokeMethod<int>('sdkInt');
      return sdk != null && sdk >= _trashMinSdk;
    } on PlatformException catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> moveToTrash(List<String> photoIds) async {
    final assets = <AssetEntity>[];
    final gone = <String>[];
    for (final id in photoIds) {
      final a = await AssetEntity.fromId(id);
      if (a == null) {
        gone.add(id); // 이미 갤러리에 없다 → 앱 기록만 지우면 된다
      } else {
        assets.add(a);
      }
    }
    final moved = assets.isEmpty
        ? const <String>[]
        : await PhotoManager.editor.android.moveToTrash(assets);
    return [...gone, ...moved];
  }
}
