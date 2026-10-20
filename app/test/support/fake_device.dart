import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/ocr_temp_files.dart';
import 'package:remine/data/device/ocr_engine.dart';

/// 1x1 투명 PNG(썸네일 디코딩 확인용).
final _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// 테스트용 갤러리. 사진 바이트는 id를 그대로 인코딩한 값이다.
class FakeGalleryReader implements GalleryReader {
  FakeGalleryReader({
    this.accessState = GalleryAccess.authorized,
    this.grantOnRequest = GalleryAccess.authorized,
    List<GalleryAlbum>? albums,
    this.photos = const [],
  }) : _albums =
           albums ??
           const [
             GalleryAlbum(
               id: 'shots',
               name: 'Screenshots',
               count: 3,
               isScreenshots: true,
             ),
             GalleryAlbum(id: 'exp', name: 'RemineExperiment', count: 2),
           ];

  GalleryAccess accessState;
  final GalleryAccess grantOnRequest;
  final List<GalleryAlbum> _albums;
  final List<GalleryPhoto> photos;

  int requested = 0;
  int reselected = 0;
  int settingsOpened = 0;
  final List<int> limits = [];

  @override
  Future<GalleryAccess> access({bool request = false}) async {
    if (request) {
      requested++;
      accessState = grantOnRequest;
    }
    return accessState;
  }

  @override
  Future<void> reselect() async => reselected++;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<List<GalleryAlbum>> albums() async => _albums;

  @override
  Future<List<GalleryPhoto>> recent(String albumId, {int limit = 300}) async {
    limits.add(limit);
    return photos.take(limit).toList();
  }

  @override
  Future<Uint8List?> thumbnail(String photoId, {int size = 220}) async =>
      photoId == 'missing' ? null : _png1x1;

  @override
  Future<Uint8List?> bytes(String photoId) async =>
      photoId == 'missing' ? null : Uint8List.fromList(photoId.codeUnits);
}

List<GalleryPhoto> fakePhotos(int n) => [
  for (var i = 0; i < n; i++)
    GalleryPhoto(
      id: 'p$i',
      fileName: 'Screenshot_$i.png',
      takenAt: DateTime(2026, 10, 19, 12).subtract(Duration(minutes: i)),
      modifiedAt: 1000 + i,
    ),
];

/// 받은 파일의 경로를 기록하고, 정해진 글자를 돌려주는 OCR.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine({this.textFor});

  final String Function(int call)? textFor;
  final List<String> paths = [];
  Set<int> failOn = {};

  @override
  String get name => 'fake';

  @override
  Future<String> recognize(File image) async {
    final call = paths.length;
    paths.add(image.path);
    if (failOn.contains(call)) throw StateError('ocr failed');
    return textFor?.call(call) ?? '글자 $call';
  }

  @override
  Future<void> close() async {}
}

/// 화면 테스트용 서비스 묶음. 임시 폴더는 [tmp](없으면 시스템 임시 폴더 아래 고정 이름).
DeviceServices fakeServices(
  FakeGalleryReader reader, {
  FakeOcrEngine? ocr,
  OcrStore? store,
  Directory? tmp,
  Directory? exportTo,
}) => DeviceServices(
  reader: reader,
  capture: DeviceCaptureService(
    reader: reader,
    ocr: ocr ?? FakeOcrEngine(),
    store: store ?? InMemoryOcrStore(),
    temp: OcrTempFiles(
      tmp ?? Directory('${Directory.systemTemp.path}/remine_fake_ocr'),
    ),
    now: () => DateTime(2026, 10, 19, 12),
  ),
  exportDir: () async => exportTo ?? Directory.systemTemp,
);
