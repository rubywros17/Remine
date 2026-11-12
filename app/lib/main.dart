import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/device/device_capture_service.dart';
import 'data/device/device_trash.dart';
import 'data/device/device_services.dart';
import 'data/device/gallery_reader.dart';
import 'data/device/local_db.dart';
import 'data/device/settings_store.dart';
import 'data/device/trash_store.dart';
import 'data/device/privacy/local_verdict_store.dart';
import 'data/device/ocr_engine.dart';
import 'data/device/ocr_store.dart';
import 'data/device/ocr_temp_files.dart';
import 'data/device/own_capture.dart';
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

/// 디버그 전용: 분석 요청 하나에 담는 장수(`--dart-define=SYNC_BATCH_SIZE=5`). 0이면 기본(20). 릴리스에서는 무시한다.
/// 배치 도입 전(요청당 5장)과 비교 측정할 때 쓴다.
const _syncBatchSize = int.fromEnvironment('SYNC_BATCH_SIZE');

/// 디버그 전용: false면 자동 동기화(OCR·서버 전송)를 끈다(`--dart-define=AUTO_SYNC=false`).
/// 디버그 화면의 [지금 동기화]로 수동 실행한다. 릴리스에서는 무시하고 항상 켠다.
const _autoSync = bool.fromEnvironment('AUTO_SYNC', defaultValue: true);

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
  final settings = SqfliteSettingsStore(db);
  final foreground = await _foregroundLog(settings);
  final trashStore = SqfliteTrashStore(
    db,
    sizeOf: (id) async => (await reader.fileSizes([id]))[id],
  );
  final ocrStore = SqfliteOcrStore(db);
  final verdicts = SqfliteLocalVerdictStore(db);
  final capture = DeviceCaptureService(
    reader: reader,
    ocr: MlKitOcrEngine(),
    store: ocrStore,
    verdicts: verdicts,
    temp: OcrTempFiles(Directory(p.join(cache.path, 'ocr_tmp'))),
    foreground: foreground,
  );
  final remote = _apiBaseAllowed
      ? _remote(reader, capture, settings, db, trashStore, await _push())
      : null;
  return DeviceServices(
    reader: reader,
    capture: capture,
    settings: settings,
    trash: DeviceTrash(
      store: trashStore,
      reader: reader,
      verdicts: verdicts,
      ocr: ocrStore,
      onChanged: remote?.sync.flushTrash,
      forgetEntries: remote?.state.removeEntries,
    ),
    remote: remote,
    exportDir: () async =>
        (await getExternalStorageDirectory()) ??
        await getApplicationSupportDirectory(),
  );
}

/// 앱이 앞에 있던 구간을 기록한다(Remine 자기 캡처 판정, 기기 밖으로 안 나감).
/// 처음 한 번은 설치 ~ 지금을 이름 없는 캡처 제외 기간으로 정한다(구간 기록이 없던 때의 자기 캡처 정리).
Future<ForegroundLog> _foregroundLog(SettingsStore settings) async {
  final log = ForegroundLog(settings);
  try {
    final ms = await const MethodChannel('remine/settings')
        .invokeMethod<int>('firstInstallTime');
    if (ms != null) {
      await log.ensureBackfill(DateTime.fromMillisecondsSinceEpoch(ms));
    }
  } on PlatformException catch (_) {
    // 설치 시각을 못 읽으면 1회 정리 없이 구간 규칙만
  }
  await log.resumed(); // 시작할 때는 상태 변화 알림이 없어서 직접 연다
  // 바인딩에 스스로 등록되므로 따로 붙잡아 둘 필요가 없다.
  AppLifecycleListener(
    onStateChange: (s) => switch (s) {
      AppLifecycleState.resumed => log.resumed(),
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => log.paused(),
      AppLifecycleState.inactive => null, // 캡처 도구·알림창이 잠깐 덮을 때 — 앱은 아직 앞에 있다
    },
  );
  return log;
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
  TrashStore trash,
  PushClient? push,
) {
  // 디버그 빌드만 요청별 "메서드 경로 → 상태 코드"를 logcat에 남긴다(본문·쿼리·토큰 없음).
  final log = kDebugMode ? debugPrint : null;
  final api = RemineApi(_apiBase, http.Client(), log: log);
  final state = SqfliteRemoteStateStore(db);
  final status = SyncStatus();
  final repository = RemoteRepository(api, state, status, trash: trash);
  final sync = SyncService(
    api: api,
    reader: reader,
    capture: capture,
    settings: settings,
    state: state,
    images: ImagePreparer(reader, const FlutterImageShrinker()),
    status: status,
    photoLimit: kDebugMode ? _syncLimit : 0,
    batchSize: kDebugMode && _syncBatchSize > 0
        ? _syncBatchSize
        : SyncService.defaultBatchSize,
    autoSync: !kDebugMode || _autoSync,
    push: push,
    log: log,
    trash: trash,
  );
  repository.onTrashChanged = sync.flushTrash;
  return RemoteServices(
    repository: repository,
    sync: sync,
    status: status,
    state: state,
    push: push,
  );
}
