import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/widgets/capture_thumb.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

class _PhotoReader extends FakeGalleryReader {
  _PhotoReader();

  final List<String> thumbRequests = [];

  @override
  Future<Uint8List?> thumbnail(String photoId, {int size = 220, int? height}) {
    thumbRequests.add(photoId);
    return super.thumbnail(photoId, size: size, height: height);
  }
}

Widget _host(Widget child, {FakeGalleryReader? reader}) {
  final app = MaterialApp(
    home: Scaffold(body: SizedBox(width: 120, height: 180, child: child)),
  );
  return reader == null
      ? app
      : DeviceScope(services: fakeServices(reader), child: app);
}

void main() {
  group('동기화는 기본 소스 앨범만 읽는다', () {
    test('RemineExperiment 같은 다른 앨범은 읽지 않는다', () async {
      final rig = await SyncRig.create(
        photos: fakePhotos(3),
        texts: {'p0': '글자'},
        albums: const [
          GalleryAlbum(id: 'exp', name: 'RemineExperiment', count: 99),
          GalleryAlbum(
            id: 'shots',
            name: 'Screenshots',
            count: 3,
            relativePath: 'DCIM/Screenshots/',
          ),
        ],
      );
      await rig.sync.run();

      expect(rig.reader.requestedAlbums, isNotEmpty);
      expect(rig.reader.requestedAlbums.toSet(), {'shots'});
    });

    test('기본 소스가 없으면 사진이 가장 많은 앨범으로 대신하지 않고 아무것도 읽지 않는다', () async {
      final rig = await SyncRig.create(
        photos: fakePhotos(3),
        texts: {'p0': '글자'},
        albums: const [
          GalleryAlbum(id: 'exp', name: 'RemineExperiment', count: 99),
          GalleryAlbum(id: 'cam', name: 'Camera', count: 500),
        ],
      );
      await rig.sync.run();

      expect(rig.reader.requestedAlbums, isEmpty);
      expect(rig.client.analyzeCalls, isEmpty);
    });
  });

  group('찍은 시각', () {
    final photoTime = DateTime(2026, 10, 8, 17, 9, 25);

    test('촬영 시각이 파일명과 맞으면 촬영 시각을 쓴다', () {
      expect(
        resolveTakenAt(
          created: photoTime.add(const Duration(seconds: 3)),
          fileName: 'Screenshot_20261008_170925_Instagram.jpg',
          modifiedAtSeconds: 1,
        ),
        photoTime.add(const Duration(seconds: 3)),
      );
    });

    test('adb push·복사로 촬영 시각이 옮긴 날(오늘)로 바뀌었으면 파일명 날짜를 쓴다', () {
      expect(
        resolveTakenAt(
          created: DateTime(2026, 10, 21, 9),
          fileName: 'Screenshot_20261008_170925_Instagram.jpg',
          modifiedAtSeconds: 1,
        ),
        photoTime,
      );
    });

    test('촬영 시각이 없으면(1970) 파일명, 그것도 없으면 수정 시각', () {
      expect(
        resolveTakenAt(
          created: DateTime.fromMillisecondsSinceEpoch(0),
          fileName: 'Screenshot_20261008_170925.png',
          modifiedAtSeconds: 1,
        ),
        photoTime,
      );
      final modified = DateTime(2026, 9, 1, 12);
      expect(
        resolveTakenAt(
          created: null,
          fileName: 'IMG_0001.jpg',
          modifiedAtSeconds: modified.millisecondsSinceEpoch ~/ 1000,
        ),
        modified,
      );
    });

    test('파일명 날짜가 말이 안 되면(13월 등) 무시한다', () {
      expect(takenAtFromFileName('Screenshot_20261308_170925.jpg'), isNull);
      expect(takenAtFromFileName('photo.jpg'), isNull);
    });

    test('서버로 가는 takenAt이 파일명 날짜를 따른다', () async {
      final taken = resolveTakenAt(
        created: DateTime(2026, 10, 21),
        fileName: 'Screenshot_20261008_170925_Instagram.jpg',
        modifiedAtSeconds: 1,
      );
      final rig = await SyncRig.create(
        photos: [
          GalleryPhoto(
            id: 'p0',
            fileName: 'Screenshot_20261008_170925_Instagram.jpg',
            takenAt: taken,
            modifiedAt: 1,
          ),
        ],
        texts: {'p0': '글자 ' * 60},
      );
      await rig.sync.run();

      expect(
        rig.client.analyzeCalls.single.utf8Text,
        contains('"takenAt":"2026-10-08T17:09:25"'),
      );
    });
  });

  group('썸네일', () {
    testWidgets('기기 모드에서는 asset id로 기기 사진을 읽어 보여 준다', (tester) async {
      final reader = _PhotoReader();
      await tester.pumpWidget(
        _host(const CaptureThumb(assetId: 'a1', seed: 1), reader: reader),
      );
      await tester.pump();
      await tester.pump();

      expect(reader.thumbRequests, ['a1']);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('사진이 없어요'), findsNothing);
    });

    testWidgets('기기에서 사진이 지워졌으면 "사진이 없어요" 자리 표시와 위에 올린 배지', (tester) async {
      await tester.pumpWidget(
        _host(
          const CaptureThumb(
            assetId: 'missing',
            seed: 1,
            child: Positioned(left: 4, bottom: 4, child: Text('10.08')),
          ),
          reader: _PhotoReader(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('사진이 없어요'), findsOneWidget);
      expect(find.text('10.08'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('아주 작은 칸에서도 자리 표시가 넘치지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceScope(
            services: fakeServices(_PhotoReader()),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CaptureThumb(assetId: 'missing', seed: 1),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('가짜 데이터 모드(기기 서비스 없음)에서는 예전 색 블록이다', (tester) async {
      await tester.pumpWidget(
        _host(const CaptureThumb(assetId: 'a1', seed: 1)),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('사진이 없어요'), findsNothing);
    });
  });

  group('분류 대기 안내', () {
    test('첫 묶음이 끝나기 전에는 남은 시간을 내지 않는다', () {
      final status = SyncStatus()..begin(15);
      expect(status.eta, isNull);
    });

    test('진행 문구는 묶음 사이에도 마지막 장수를 유지한다', () {
      final status = SyncStatus()..begin(15);
      expect(status.progressMessage, '분류를 준비하는 중이에요…');
      status.setWaiting(15);
      expect(status.progressMessage, '15장을 분류하는 중이에요…');
      status.setWaiting(0);
      expect(status.progressMessage, '15장을 분류하는 중이에요…');
      status.begin(3);
      expect(status.progressMessage, '분류를 준비하는 중이에요…');
    });

    test('동기화가 끝나면 대기 표시도 꺼진다', () {
      final status = SyncStatus()..begin(5);
      status.setWaiting(5);
      status.finish();
      expect(status.waiting, 0);
    });

    test('동기화는 서버 응답을 기다리는 동안 대기 상태를 알리고 끝나면 끈다', () async {
      final rig = await SyncRig.create(
        photos: fakePhotos(3),
        texts: {for (var i = 0; i < 3; i++) 'p$i': '글자 ' * 60},
      );
      final seen = <int>[];
      rig.status.addListener(() => seen.add(rig.status.waiting));
      await rig.sync.run();

      expect(seen, contains(3));
      expect(rig.status.waiting, 0);
    });
  });
}
