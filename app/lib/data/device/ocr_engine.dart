import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 기기 안 OCR. 원문은 로그에 남기지 않는다(호출한 쪽도 글자 수만 기록한다).
abstract interface class OcrEngine {
  String get name;
  Future<String> recognize(File image);
  Future<void> close();
}

/// ML Kit 한국어. 모델은 앱에 번들(android/app/build.gradle.kts)이라 첫 실행 다운로드 없이 오프라인으로 동작한다.
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.korean,
  );

  @override
  String get name => 'mlkit-korean';

  @override
  Future<String> recognize(File image) async {
    final result = await _recognizer.processImage(InputImage.fromFile(image));
    return result.text;
  }

  @override
  Future<void> close() => _recognizer.close();
}
