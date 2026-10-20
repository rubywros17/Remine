import 'dart:ui';

import 'support/layout_matrix.dart';

/// 앱 폰트를 못 불러온 경우(웹에서 폰트 로딩 전/실패, 기본 폰트는 글자 폭이 훨씬 넓다)에도 깨지지 않는지.
void main() {
  defineLayoutMatrix(
    realFonts: false,
    cases: const [
      ('폰트 없음 360x640', Size(360, 640), 1.0),
      ('폰트 없음 390x844', Size(390, 844), 1.0),
      ('폰트 없음 320x480', Size(320, 480), 1.0),
      ('폰트 없음 280x653', Size(280, 653), 1.0),
      ('폰트 없음 1280x720', Size(1280, 720), 1.0),
    ],
  );
}
