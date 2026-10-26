import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/device/device_capture_service.dart';
import 'data/device/device_services.dart';
import 'data/device/gallery_reader.dart';
import 'data/device/local_db.dart';
import 'data/device/settings_store.dart';
import 'data/device/privacy/local_verdict_store.dart';
import 'data/device/ocr_engine.dart';
import 'data/device/ocr_store.dart';
import 'data/device/ocr_temp_files.dart';
import 'data/device/photo_manager_gallery_reader.dart';
import 'data/remote/api_client.dart';
import 'data/remote/image_prep.dart';
import 'data/remote/push.dart';
import 'data/remote/remote_repository.dart';
import 'data/remote/remote_services.dart';
import 'data/remote/remote_state_store.dart';
import 'data/remote/sync_service.dart';
import 'data/remote/sync_status.dart';

/// 데이터 모드: 기본은 가짜 데이터(크롬·테스트), `--dart-define=DATA=device`면 폰 갤러리 + 기기 안 OCR.
const _dataMode = String.fromEnvironment('DATA');

/// 서버 주소(`--dart-define=API_BASE=http://localhost:8080`). 비어 있으면 서버 연동 없이 동작한다.
/// 릴리스 빌드는 HTTPS 주소만 받는다(평문 HTTP는 디버그 빌드의 network_security_config에서만 열려 있다).
const _apiBase = String.fromEnvironment('API_BASE');

/// 디버그 전용: 이 장수만 서버로 보낸다(`--dart-define=SYNC_LIMIT=15`). 0이면 제한 없음. 릴리스에서는 무시한다.
const _syncLimit = int.fromEnvironment('SYNC_LIMIT');

bool get _apiBaseAllowed =>
    _apiBase.isNotEmpty && (kDebugMode || _apiBase.startsWith('https://'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    RemineApp(
      // 개발용 시작 화면: flutter run --dart-define=START_SCREEN=analysis
      startScreen: const String.fromEnvironment('START_SCREEN'),
      device: _dataMode == 'device' ? await _deviceServices() : null,
    ),
  );
}

Future<DeviceServices> _deviceServices() async {
  final cache =
      await getTemporaryDirectory(); // 앱 캐시 폴더 — OCR 임시 복사본은 여기 안에서만 만들고 지운다
  final reader = PhotoManagerGalleryReader();
  final db = LocalDb();
  final capture = DeviceCaptureService(
    reader: reader,
    ocr: MlKitOcrEngine(),
    store: SqfliteOcrStore(db),
    verdicts: SqfliteLocalVerdictStore(db),
    temp: OcrTempFiles(Directory(p.join(cache.path, 'ocr_tmp'))),
  );
  final settings = SqfliteSettingsStore(db);
  return DeviceServices(
    reader: reader,
    capture: capture,
    settings: settings,
    remote: _apiBaseAllowed
        ? _remote(reader, capture, settings, db, await _push())
        : null,
    exportDir: () async =>
        (await getExternalStorageDirectory()) ??
        await getApplicationSupportDirectory(),
  );
}

/// 푸시는 서버 연동(기기 모드 + API_BASE)일 때만 켠다. 크롬·테스트는 Firebase를 건드리지 않는다.
/// 설정 파일(google-services.json)은 Gradle 플러그인이 빌드에 넣는다. 초기화에 실패하면 푸시 없이 동작한다.
Future<PushClient?> _push() async {
  try {
    await Firebase.initializeApp();
    return FirebasePushClient();
  } catch (_) {
    return null;
  }
}

RemoteServices _remote(
  GalleryReader reader,
  DeviceCaptureService capture,
  SettingsStore settings,
  LocalDb db,
  PushClient? push,
) {
  final api = RemineApi(_apiBase, http.Client());
  final state = SqfliteRemoteStateStore(db);
  final status = SyncStatus();
  return RemoteServices(
    repository: RemoteRepository(api, state, status),
    sync: SyncService(
      api: api,
      reader: reader,
      capture: capture,
      settings: settings,
      state: state,
      images: ImagePreparer(reader, const FlutterImageShrinker()),
      status: status,
      photoLimit: kDebugMode ? _syncLimit : 0,
      push: push,
    ),
    status: status,
    state: state,
    push: push,
  );
}
