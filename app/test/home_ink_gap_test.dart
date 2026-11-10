import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:remine/widgets/small_widgets.dart';

/// 실제 폰트로 홈을 그려 픽셀을 훑고, 보이는 글자 끝 기준 간격을 잰다.
/// (제목 글자 아래 끝 → 카드 위, 카드 아래 → 서랍 제목 글자 위 끝). AppHome의 글자 보정값을 다시 잴 때도 쓴다.
Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<(double, double)> _visibleGaps(
  WidgetTester tester,
  Size size,
  double scale,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final now = DateTime(2026, 10, 19, 12);
  await tester.pumpWidget(
    RepaintBoundary(
      child: RemineApp(
        repository: FakeScreenshotRepository(now: () => now),
        now: () => now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final bytes = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  }))!;
  final width = size.width.toInt();
  bool dark(int x, int y) {
    final i = (y * width + x) * 4;
    final luma =
        (bytes.getUint8(i) * 3 +
            bytes.getUint8(i + 1) * 6 +
            bytes.getUint8(i + 2)) ~/
        10;
    return luma < 100;
  }

  // 글자가 있는 줄의 처음·끝(끝은 그 줄 아래 경계).
  (int, int) inkRows(Rect r) {
    int? first, last;
    for (var y = r.top.floor() - 4; y < r.bottom.ceil() + 4; y++) {
      for (var x = r.left.ceil(); x < r.right.floor(); x++) {
        if (dark(x, y)) {
          first ??= y;
          last = y + 1;
          break;
        }
      }
    }
    return (first!, last!);
  }

  final title = inkRows(tester.getRect(find.byType(HighlighterText)));
  final card = tester.getRect(find.byType(InterestCard));
  final drawer = inkRows(tester.getRect(find.text('내 캡처 서랍')));
  return (card.top - title.$2, drawer.$1 - card.bottom);
}

void main() {
  setUpAll(() async {
    await _loadFont('Pretendard', [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
    ]);
    await _loadFont('SpaceGrotesk', ['assets/fonts/SpaceGrotesk.ttf']);
  });

  for (final scale in const [1.0, 1.3]) {
    for (final size in const [Size(360, 800), Size(412, 915)]) {
      testWidgets('제목-카드와 카드-서랍 제목이 보이는 글자 끝 기준으로 같다 $size ×$scale', (
        tester,
      ) async {
        final (above, below) = await _visibleGaps(tester, size, scale);
        // 픽셀 단위로 재므로 1.5px까지는 같은 것으로 본다.
        expect(
          (above - below).abs(),
          lessThanOrEqualTo(1.5),
          reason: '제목-카드 $above, 카드-서랍 제목 $below',
        );
      });
    }
  }
}
