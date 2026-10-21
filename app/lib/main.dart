import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/device/device_capture_service.dart';
import 'data/device/device_services.dart';
import 'data/device/ocr_engine.dart';
import 'data/device/ocr_store.dart';
import 'data/device/ocr_temp_files.dart';
import 'data/device/photo_manager_gallery_reader.dart';

/// 데이터 모드: 기본은 가짜 데이터(크롬·테스트), `--dart-define=DATA=device`면 폰 갤러리 + 기기 안 OCR.
const _dataMode = String.fromEnvironment('DATA');

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
  return DeviceServices(
    reader: reader,
    capture: DeviceCaptureService(
      reader: reader,
      ocr: MlKitOcrEngine(),
      store: SqfliteOcrStore(),
      temp: OcrTempFiles(Directory(p.join(cache.path, 'ocr_tmp'))),
    ),
    exportDir: () async =>
        (await getExternalStorageDirectory()) ??
        await getApplicationSupportDirectory(),
  );
}
