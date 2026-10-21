import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/ocr_engine.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/ocr_temp_files.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/remote/api_client.dart';
import 'package:remine/data/remote/image_prep.dart';
import 'package:remine/data/remote/remote_repository.dart';
import 'package:remine/data/remote/remote_services.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_service.dart';
import 'package:remine/data/remote/sync_status.dart';

import 'fake_device.dart';

/// 보낸 요청 하나. 본문 바이트 전체를 보관해 테스트가 "무엇이 실렸는지" 검사한다.
class SentRequest {
  SentRequest(this.method, this.path, this.body);

  final String method;
  final String path;
  final Uint8List body;

  /// 바이너리가 섞여 있어도 글자 검사를 할 수 있게 latin1로 푼 본문.
  String get text => latin1.decode(body);

  /// UTF-8로 푼 본문(한글 검사용). 이미지 바이트가 섞이면 깨지므로 JSON 요청에만 쓴다.
  String get utf8Text => utf8.decode(body, allowMalformed: true);

  bool get isMultipart =>
      text.toLowerCase().contains('content-disposition: form-data');
}

typedef Responder = FutureOr<http.StreamedResponse> Function(
  SentRequest request,
);

http.StreamedResponse jsonResponse(Object body, [int status = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );

/// 모든 요청을 기록하는 가짜 HTTP 클라이언트. 기본 응답은 서버 계약(spec 9장)을 따른다.
class RecordingClient extends http.BaseClient {
  RecordingClient({this.responder});

  final Responder? responder;
  final List<SentRequest> sent = [];

  /// 이 목록에 든 assetId는 analyze에서 `failed`로 돌려준다.
  final Map<String, String> failWith = {};

  /// 한 번만 예외를 던질 요청 횟수(0이면 안 던짐). 네트워크 오류 시뮬레이션.
  Object? throwOnSend;

  Iterable<SentRequest> get analyzeCalls =>
      sent.where((r) => r.path == '/api/screenshots/analyze');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final req = SentRequest(request.method, request.url.path, body);
    sent.add(req);
    final error = throwOnSend;
    if (error != null) throw error;
    if (responder != null) return responder!(req);
    return defaultFor(req);
  }

  http.StreamedResponse defaultFor(SentRequest r) {
    switch ('${r.method} ${r.path}') {
      case 'POST /api/devices':
        return jsonResponse({'deviceId': 7});
      case 'GET /api/config':
        return jsonResponse({
          'imageThresholdChars': 150,
          'maxBatchSize': 20,
          'imageMaxBytes': 1048576,
          'imageMaxLongSide': 1024,
          'imageContentType': 'image/jpeg',
          'maxRequestBytes': 12582912,
        });
      case 'POST /api/screenshots/analyze':
        final ids = RegExp(r'"localAssetId":"([^"]+)"')
            .allMatches(r.text)
            .map((m) => m.group(1)!)
            .toList();
        return jsonResponse({
          'analyzed': [
            for (final id in ids)
              if (!failWith.containsKey(id))
                {
                  'localAssetId': id,
                  'category': 'INFO',
                  'tags': <String>[],
                  'summary': '',
                },
          ],
          'skipped': <String>[],
          'failed': [
            for (final id in ids)
              if (failWith.containsKey(id))
                {'localAssetId': id, 'reason': failWith[id]},
          ],
        });
      default:
        return jsonResponse({}, 404);
    }
  }
}

/// EXIF(GPS 포함) APP1·XMP·주석이 든 가짜 JPEG. 압축 라이브러리가 메타데이터를 남겼을 때를 흉내 낸다.
Uint8List jpegWithMetadata() {
  List<int> segment(int marker, List<int> payload) => [
    0xFF,
    marker,
    ((payload.length + 2) >> 8) & 0xFF,
    (payload.length + 2) & 0xFF,
    ...payload,
  ];
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    ...segment(0xE0, [...'JFIF'.codeUnits, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
    ...segment(0xE1, [
      ...'Exif'.codeUnits,
      0,
      0,
      ...'GPSLatitude 37.5665 GPSLongitude 126.9780 Make=SAMSUNG'.codeUnits,
    ]),
    ...segment(0xE1, [
      ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
      0,
      ...'<x:xmpmeta/>'.codeUnits,
    ]),
    ...segment(0xFE, 'secret comment'.codeUnits),
    ...segment(0xDB, List.filled(65, 1)), // DQT
    0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, // SOS
    1, 2, 3, 4, 5, 6, 7, 8,
    0xFF, 0xD9, // EOI
  ]);
}

class FakeShrinker implements ImageShrinker {
  FakeShrinker({Uint8List? output, this.sizeFor})
    : output = output ?? jpegWithMetadata();

  final Uint8List output;

  /// 호출(품질·긴 변)에 따라 결과를 바꿀 때.
  final Uint8List Function(int maxLongSide, int quality)? sizeFor;
  final List<(int, int)> calls = [];

  @override
  Future<Uint8List?> shrink(
    Uint8List original, {
    required int maxLongSide,
    required int quality,
  }) async {
    calls.add((maxLongSide, quality));
    return sizeFor?.call(maxLongSide, quality) ?? output;
  }
}

/// 임시 복사본 파일의 내용(= 가짜 갤러리가 만든 assetId 바이트)으로 정해진 텍스트를 돌려주는 OCR.
class MapOcrEngine implements OcrEngine {
  MapOcrEngine(this.textByAsset);

  final Map<String, String> textByAsset;
  final List<String> recognized = [];

  @override
  String get name => 'fake';

  @override
  Future<String> recognize(File image) async {
    final id = utf8.decode(await image.readAsBytes());
    recognized.add(id);
    return textByAsset[id] ?? '';
  }

  @override
  Future<void> close() async {}
}

/// 동기화 테스트 한 묶음.
class SyncRig {
  SyncRig._(
    this.client,
    this.reader,
    this.ocr,
    this.capture,
    this.settings,
    this.state,
    this.status,
    this.shrinker,
    this.sync,
    this.repository,
    this.batches,
  );

  final RecordingClient client;
  final FakeGalleryReader reader;
  final MapOcrEngine ocr;
  final DeviceCaptureService capture;
  final InMemorySettingsStore settings;
  final InMemoryRemoteStateStore state;
  final SyncStatus status;
  final FakeShrinker shrinker;
  final SyncService sync;
  final RemoteRepository repository;

  /// 배치가 끝날 때마다 쌓이는 호출 시점의 `status.done`.
  final List<int> batches;

  RemoteServices get remote => RemoteServices(
    repository: repository,
    sync: sync,
    status: status,
    state: state,
  );

  static Future<SyncRig> create({
    required List<GalleryPhoto> photos,
    Map<String, String> texts = const {},
    bool? consent = true,
    RecordingClient? client,
    FakeShrinker? shrinker,
    int photoLimit = 0,
    List<GalleryAlbum>? albums,
  }) async {
    final reader = FakeGalleryReader(photos: photos, albums: albums);
    final ocr = MapOcrEngine(texts);
    final tmp = await Directory.systemTemp.createTemp('remine_sync_');
    final capture = DeviceCaptureService(
      reader: reader,
      ocr: ocr,
      store: InMemoryOcrStore(),
      temp: OcrTempFiles(tmp),
      now: () => DateTime(2026, 10, 21, 12),
    );
    final settings = InMemorySettingsStore(consent);
    final state = InMemoryRemoteStateStore();
    final status = SyncStatus();
    final c = client ?? RecordingClient();
    final api = RemineApi('http://localhost:8080', c);
    final shrink = shrinker ?? FakeShrinker();
    final batches = <int>[];
    final sync = SyncService(
      api: api,
      reader: reader,
      capture: capture,
      settings: settings,
      state: state,
      images: ImagePreparer(reader, shrink),
      status: status,
      photoLimit: photoLimit,
      onBatchDone: () => batches.add(status.done),
      now: () => DateTime(2026, 10, 21, 12),
    );
    return SyncRig._(
      c,
      reader,
      ocr,
      capture,
      settings,
      state,
      status,
      shrink,
      sync,
      RemoteRepository(api, state, status),
      batches,
    );
  }
}

/// 사진 id가 곧 OCR 텍스트 키다. [names]로 파일명을 지정하지 않은 사진은 `Screenshot_N.png`.
List<GalleryPhoto> photosNamed(Map<String, String> fileNameById) => [
  for (final (i, e) in fileNameById.entries.indexed)
    GalleryPhoto(
      id: e.key,
      fileName: e.value,
      takenAt: DateTime(2026, 10, 21, 12).subtract(Duration(minutes: i)),
      modifiedAt: 1000 + i,
    ),
];
