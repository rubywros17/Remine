import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/widgets/small_widgets.dart';
import 'package:remine/widgets/wordmark.dart';

import 'fake_device.dart';

/// 여러 화면 크기·글자 크기에서 모든 화면이 RenderFlex overflow 없이 그려지는지 확인한다.
/// Flutter는 넘침을 예외로 보고하므로, 화면을 띄우고 조작하는 동안 보고된 오류를 전부 모아
/// "어떤 위젯이 몇 px 넘쳤는지"를 실패 메시지에 나열한다.
final _now = DateTime(2026, 10, 19, 12, 0);

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

/// [body]를 실행하며 보고된 Flutter 오류를 모아 한 줄 요약 목록으로 돌려준다.
Future<List<String>> _errorsDuring(Future<void> Function() body) async {
  final original = FlutterError.onError;
  final errors = <String>[];
  FlutterError.onError = (details) {
    final text = details.toString();
    final overflow = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)')
        .firstMatch(text);
    final widget = RegExp(r'error-causing widget was:\s*\n\s*(.+)')
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    final where = RegExp(r'lib/([\w/]+\.dart:\d+)').firstMatch(text)?.group(1);
    errors.add(
      overflow != null
          ? 'overflow ${overflow.group(1)}px ${overflow.group(2)} @ ${where ?? widget ?? '?'}'
          : text.split('\n').take(2).join(' / '),
    );
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  double scale, {
  String start = '',
  DeviceServices? device,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now),
      now: () => _now,
      startScreen: start,
      device: device,
    ),
  );
  await tester.pumpAndSettle();
}

/// 요소가 화면 밖(가로 스크롤 줄 등)에 있으면 보이게 한 뒤 누른다. 너무 작은 화면에서는 누를 수 없어도 넘어간다.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  // 작은 화면에서는 지연 생성되는 목록(ListView) 아래쪽이라 아직 만들어지지 않았을 수 있다 → 위로 밀어 올려 만든다.
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await tester.pump();
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle(); // 스크롤 애니메이션이 끝난 뒤 눌러야 위치가 맞는다
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void _expectClean(String where, List<String> errors) {
  expect(errors, isEmpty, reason: '$where\n  ${errors.toSet().join('\n  ')}');
}

/// [realFonts]가 false면 앱 폰트를 불러오지 않는다(테스트 기본 폰트는 글자 폭이 훨씬 넓다 = 웹에서 폰트를 못 불러온 최악의 경우).
void defineLayoutMatrix({
  required bool realFonts,
  required List<(String, Size, double)> cases,
}) {
  if (realFonts) {
    setUpAll(() async {
      // 실제 글자 폭으로 재기 위해 앱 폰트를 불러온다(기본 테스트 폰트는 글자 폭이 다르다).
      await _loadFont('Pretendard', [
        'assets/fonts/Pretendard-Regular.otf',
        'assets/fonts/Pretendard-SemiBold.otf',
        'assets/fonts/Pretendard-Bold.otf',
      ]);
      await _loadFont('SpaceGrotesk', ['assets/fonts/SpaceGrotesk.ttf']);
      await _loadFont(
        'packages/lucide_icons_flutter/Lucide',
        [
          '${Platform.environment['PUB_CACHE'] ?? ''}/hosted/pub.dev/lucide_icons_flutter-4.0.0/assets/lucide.ttf',
        ].where((f) => File(f).existsSync()).toList(),
      );
    });
  }

  for (final (name, size, scale) in cases) {
    final label = '$name 글자 $scale배';

    testWidgets('홈 · $label', (tester) async {
      final errors = await _errorsDuring(() => _pump(tester, size, scale));
      _expectClean('홈 $label', errors);
    });

    testWidgets('카테고리 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('문화생활')); // 이름이 가장 긴 카테고리
        expect(
          find.byType(BackButtonCircle),
          findsOneWidget,
          reason: '카테고리 화면으로 이동하지 못함',
        );
        await _tap(tester, find.text('#드라마')); // 태그 필터 상태
      });
      _expectClean('카테고리 $label', errors);
    });

    testWidgets('상세 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건')); // 관심사 카드 → 카테고리(태그 선택)
        await _tap(tester, find.byType(Hero)); // 첫 타일 → 상세("더 보기" 버튼이 있는 항목)
        expect(
          find.textContaining('같은 관심사 캡처'),
          findsOneWidget,
          reason: '상세 화면(더 보기 버튼)이 아님',
        );
      });
      _expectClean('상세 $label', errors);
    });

    testWidgets('상세 넘기기·위치 알약 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건'));
        await _tap(tester, find.byType(Hero));
        expect(find.text('1 / 4'), findsOneWidget, reason: '위치 알약이 없다');
        await tester.fling(
          find.byType(PageView),
          Offset(-size.width * 0.5, 0),
          1500,
        );
        await tester.pumpAndSettle();
        expect(find.text('2 / 4'), findsOneWidget);
      });
      _expectClean('상세 넘기기 $label', errors);
    });

    testWidgets('상세 던지는 중(휴지통 아이콘·배경) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건'));
        await _tap(tester, find.byType(Hero));
        final card = find.descendant(
          of: find.byType(PageView),
          matching: find.byType(Hero),
        );
        // 위로 끌어 휴지통 아이콘이 나타난 중간 상태, 기준선을 넘은 강조 상태를 차례로 그려 본다.
        final g = await tester.startGesture(tester.getCenter(card));
        await g.moveBy(const Offset(0, -(kTouchSlop + 2)));
        await g.moveBy(const Offset(0, -80));
        await tester.pump();
        expect(find.byKey(const ValueKey('trash-target')), findsOneWidget);
        await g.moveBy(Offset(0, -size.height * 0.4));
        await tester.pump();
        await g.moveBy(Offset(0, size.height * 0.4 + 80)); // 놓지 않고 제자리로
        await g.up();
        await tester.pumpAndSettle();
      });
      _expectClean('상세 던지는 중 $label', errors);
    });

    testWidgets('상세 ⋯ 메뉴 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건'));
        await _tap(tester, find.byType(Hero));
        // 아주 낮은 화면에서는 위쪽 끝으로 스크롤하면 상단 바에 가려지므로 가운데로 맞춘 뒤 누른다.
        final menu = find.byIcon(LucideIcons.ellipsis);
        Scrollable.ensureVisible(
          tester.element(menu.first),
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        await tester.tap(menu.first);
        await tester.pumpAndSettle();
        expect(find.text('휴지통으로'), findsOneWidget, reason: '메뉴가 열리지 않았다');
      });
      _expectClean('상세 메뉴 $label', errors);
    });

    testWidgets('수정 시트 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건'));
        await _tap(tester, find.byType(Hero));
        await _tap(tester, find.text('쇼핑')); // 카테고리 칩 → 시트
        expect(find.text('이거 어디 서랍이야?'), findsOneWidget);
      });
      _expectClean('수정 시트 $label', errors);
    });

    testWidgets('사진 권한 거부 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final reader = FakeGalleryReader(
          accessState: GalleryAccess.denied,
          grantOnRequest: GalleryAccess.denied,
        );
        await _pump(tester, size, scale, device: fakeServices(reader));
        expect(find.text('설정 열기'), findsOneWidget);
      });
      _expectClean('권한 거부 $label', errors);
    });

    testWidgets('사진 일부만 허용(안내 띠 + 홈) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final reader = FakeGalleryReader(grantOnRequest: GalleryAccess.limited);
        await _pump(tester, size, scale, device: fakeServices(reader));
        expect(find.text('다시 고르기'), findsOneWidget);
        expect(find.byType(Wordmark), findsOneWidget);
      });
      _expectClean('일부 허용 $label', errors);
    });

    testWidgets('디버그 OCR 측정 화면 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final reader = FakeGalleryReader(photos: fakePhotos(40));
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(home: DebugOcrScreen(services: fakeServices(reader))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('전체 선택'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('album-exp')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      });
      _expectClean('디버그 OCR $label', errors);
    });

    testWidgets('첫 분석 · $label', (tester) async {
      final errors = await _errorsDuring(
        () => _pump(tester, size, scale, start: 'analysis'),
      );
      _expectClean('첫 분석 $label', errors);
    });
  }
}
