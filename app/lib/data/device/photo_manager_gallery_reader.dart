import 'dart:typed_data';

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
      photos.add(
        GalleryPhoto(
          id: a.id,
          fileName: await a.titleAsync,
          takenAt: a.createDateTime,
          modifiedAt: a.modifiedDateSecond ?? 0,
        ),
      );
    }
    return photos;
  }

  @override
  Future<Uint8List?> thumbnail(String photoId, {int size = 220}) async {
    final a = await AssetEntity.fromId(photoId);
    return a?.thumbnailDataWithSize(ThumbnailSize.square(size));
  }

  @override
  Future<Uint8List?> bytes(String photoId) async {
    final a = await AssetEntity.fromId(photoId);
    return a?.originBytes;
  }
}
