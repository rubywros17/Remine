import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/ocr_export.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/ocr_temp_files.dart';

import 'support/fake_device.dart';

void main() {
  late Directory sandbox;
  late Directory cache; // 앱 캐시 폴더 역할
  late Directory pictures; // 사진 원본 폴더 역할

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('remine_test_');
    cache = Directory(p.join(sandbox.path, 'cache', 'ocr'));
    pictures = Directory(p.join(sandbox.path, 'Pictures'))..createSync();
  });
  tearDown(() => sandbox.delete(recursive: true));

  group('OcrTempFiles', () {
    test('캐시 폴더 안 복사본은 지우고, 밖(원본 경로)은 절대 지우지 않는다', () async {
      final temp = OcrTempFiles(cache);
      final copy = await temp.write(Uint8List.fromList([1, 2, 3]));
      final original = File(p.join(pictures.path, 'Screenshot_1.png'))
        ..writeAsBytesSync([9, 9]);

      expect(await temp.dispose(original), isFalse);
      expect(original.existsSync(), isTrue);

      expect(await temp.dispose(copy), isTrue);
      expect(copy.existsSync(), isFalse);
    });

    test('폴더 이름만 비슷한 형제 경로도 지우지 않는다', () async {
      final temp = OcrTempFiles(cache);
      final sibling = File(p.join('${cache.path}_other', 'a.png'))
        ..createSync(recursive: true);

      expect(await temp.dispose(sibling), isFalse);
      expect(sibling.existsSync(), isTrue);
    });

    test('clear는 캐시 폴더의 복사본만 비운다', () async {
      final temp = OcrTempFiles(cache);
      final a = await temp.write(Uint8List.fromList([1]));
      final original = File(p.join(pictures.path, 'keep.png'))
        ..writeAsBytesSync([1]);

      await temp.clear();

      expect(a.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
    });
  });

  group('DeviceCaptureService', () {
    late FakeOcrEngine ocr;
    late InMemoryOcrStore store;

    DeviceCaptureService make(FakeGalleryReader reader) {
      return DeviceCaptureService(
        reader: reader,
        ocr: ocr,
        store: store,
        temp: OcrTempFiles(cache),
        now: () => DateTime(2026, 10, 19, 12),
      );
    }

    setUp(() {
      ocr = FakeOcrEngine();
      store = InMemoryOcrStore();
    });

    test('최근 300장까지만 읽는다', () async {
      final reader = FakeGalleryReader(photos: fakePhotos(350));
      final photos = await make(reader).recent('shots');

      expect(photos, hasLength(300));
      expect(reader.limits, [300]);
    });

    test('OCR 입력은 앱 캐시의 복사본이고, 끝나면 지워지며, 사진 원본 폴더는 그대로다', () async {
      final original = File(p.join(pictures.path, 'Screenshot_0.png'))
        ..writeAsBytesSync([7]);
      final reader = FakeGalleryReader(photos: fakePhotos(2));

      await make(reader).run(reader.photos);

      expect(ocr.paths, hasLength(2));
      for (final path in ocr.paths) {
        expect(p.isWithin(cache.path, path), isTrue);
        expect(File(path).existsSync(), isFalse);
      }
      expect(original.existsSync(), isTrue);
    });

    test('OCR가 실패해도 복사본은 지워진다', () async {
      ocr.failOn = {0};
      final reader = FakeGalleryReader(photos: fakePhotos(1));

      final run = await make(reader).run(reader.photos);

      expect(run.failed, 1);
      expect(cache.listSync(), isEmpty);
    });

    test('글자 수는 공백을 뺀 값이고 결과를 저장한다', () async {
      ocr = FakeOcrEngine(textFor: (_) => '가 나\n다 abc');
      final reader = FakeGalleryReader(photos: fakePhotos(1));

      final run = await make(reader).run(reader.photos);

      expect(run.records.single.charCount, 6);
      expect((await store.find('p0'))!.text, '가 나\n다 abc');
    });

    test('바뀌지 않은 사진은 다시 OCR하지 않고, 바뀐 사진만 다시 한다', () async {
      final reader = FakeGalleryReader(photos: fakePhotos(2));
      final service = make(reader);
      await service.run(reader.photos);
      expect(ocr.paths, hasLength(2));

      final second = await service.run(reader.photos);
      expect(ocr.paths, hasLength(2));
      expect(second.skipped, 2);

      final changed = [
        reader.photos[0],
        GalleryPhoto(
          id: 'p1',
          fileName: 'Screenshot_1.png',
          takenAt: DateTime(2026),
          modifiedAt: 5000,
        ),
      ];
      await service.run(changed);
      expect(ocr.paths, hasLength(3));
    });

    test('한 장이 실패해도 나머지는 계속하고, 진행률을 알린다', () async {
      ocr.failOn = {1};
      final reader = FakeGalleryReader(photos: fakePhotos(3));
      final progress = <int>[];

      final run = await make(reader).run(
        reader.photos,
        onProgress: (done, total) => progress.add(done),
      );

      expect(run.records, hasLength(2));
      expect(run.failed, 1);
      expect(progress, [1, 2, 3]);
    });

    test('취소하면 거기서 멈춘다', () async {
      final reader = FakeGalleryReader(photos: fakePhotos(5));
      var cancel = false;

      final run = await make(reader).run(
        reader.photos,
        onProgress: (done, _) => cancel = done >= 2,
        isCancelled: () => cancel,
      );

      expect(run.records, hasLength(2));
    });

    test('OCR 원문이 print·debugPrint 로그로 나가지 않는다', () async {
      ocr = FakeOcrEngine(textFor: (_) => '비밀번호는 1234567');
      final reader = FakeGalleryReader(photos: fakePhotos(2));
      final logs = <String>[];

      await runZoned(
        () => make(reader).run(reader.photos),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => logs.add(line),
        ),
      );

      expect(logs.where((l) => l.contains('1234567')), isEmpty);
    });
  });

  group('OcrExport', () {
    test('파일명·글자 수·텍스트를 JSON으로 만든다', () {
      final json = OcrExport.build(
        [
          OcrRecord(
            assetId: 'a',
            fileName: 'Screenshot_1.png',
            modifiedAt: 1,
            text: '안녕 하세요',
            charCount: 5,
            ocrAt: DateTime(2026),
            engine: 'fake',
          ),
        ],
        engine: 'mlkit-korean',
        exportedAt: DateTime(2026, 10, 19, 12),
      );

      final item = (json['items']! as List).single as Map;
      expect(item, {
        'fileName': 'Screenshot_1.png',
        'charCount': 5,
        'text': '안녕 하세요',
      });
      expect(json['engine'], 'mlkit-korean');
      expect(json['count'], 1);
    });

    test('파일로 쓰면 UTF-8 JSON으로 다시 읽힌다', () async {
      final file = await OcrExport.write(
        Directory(p.join(sandbox.path, 'out')),
        [
          OcrRecord(
            assetId: 'a',
            fileName: 'x.png',
            modifiedAt: 1,
            text: '한글',
            charCount: 2,
            ocrAt: DateTime(2026),
            engine: 'fake',
          ),
        ],
        engine: 'fake',
        now: DateTime(2026, 10, 19, 12, 5, 9),
      );

      expect(p.basename(file.path), 'ocr-export-20261019-120509.json');
      final back = jsonDecode(await file.readAsString()) as Map;
      expect(((back['items'] as List).single as Map)['text'], '한글');
    });
  });

  group('네트워크 없음', () {
    test('pubspec에 HTTP 계열 의존성이 없다', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final dep in ['http:', 'dio:', 'firebase_', 'web_socket']) {
        expect(pubspec.contains(dep), isFalse, reason: dep);
      }
    });

    test('lib 코드에 네트워크 호출이 없다', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        if (RegExp(r'HttpClient|package:http/|package:dio/|Socket\.connect|WebSocket')
            .hasMatch(s)) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });
  });
}
