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
    final path = await AssetPathEntity.fromId(
      albumId,
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    final assets = await path.getAssetListRange(start: 0, end: limit);
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
  Future<Uint8List?> bytes(String photoId) async {
    final a = await AssetEntity.fromId(photoId);
    return a?.originBytes;
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
