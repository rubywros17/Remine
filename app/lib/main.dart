import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  runApp(
    const RemineApp(
      // 개발용 시작 화면: flutter run --dart-define=START_SCREEN=analysis
      startScreen: String.fromEnvironment('START_SCREEN'),
    ),
  );
}
