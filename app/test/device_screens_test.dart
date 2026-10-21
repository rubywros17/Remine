import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/widgets/wordmark.dart';

import 'support/fake_device.dart';

Future<void> _pumpApp(WidgetTester tester, FakeGalleryReader reader) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RemineApp(device: fakeServices(reader)));
  await tester.pumpAndSettle();
}

/// 실제 파일 입출력이 끝날 시간을 준다(testWidgets는 가짜 시계라 IO가 진행되지 않는다).
Future<void> _io(WidgetTester tester) async {
  // IO는 실제 시간에, 그 뒤의 이어받기(await 다음 줄)는 가짜 시계에서 돌아가므로 번갈아 진행한다.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
}

void main() {
  group('사진 권한', () {
    testWidgets('허용이면 바로 앱이 보이고 안내 띠는 없다', (tester) async {
      await _pumpApp(tester, FakeGalleryReader());

      expect(find.byType(Wordmark), findsOneWidget);
      expect(find.text('다시 고르기'), findsNothing);
    });

    testWidgets('일부만 허용이면 안내 띠가 뜨고, 다시 고르기가 시스템 선택창을 연다', (tester) async {
      final reader = FakeGalleryReader(grantOnRequest: GalleryAccess.limited);
      await _pumpApp(tester, reader);

      expect(find.textContaining('새 스크린샷은 자동으로 가져올 수 없어'), findsOneWidget);
      expect(find.byType(Wordmark), findsOneWidget); // 고른 사진으로는 계속 쓸 수 있다

      await tester.tap(find.text('다시 고르기'));
      await tester.pumpAndSettle();
      expect(reader.reselected, 1);
    });

    testWidgets('거부면 안내 화면이 뜨고, 설정 열기가 설정을 연다', (tester) async {
      final reader = FakeGalleryReader(
        accessState: GalleryAccess.denied,
        grantOnRequest: GalleryAccess.denied,
      );
      await _pumpApp(tester, reader);

      expect(find.byType(Wordmark), findsNothing);
      expect(find.text('사진을 볼 수 있어야 해'), findsOneWidget);
      expect(reader.requested, 1); // 시작할 때 한 번 요청했다
      // 요청했는데도 거부 → 팝업이 안 뜰 수 있다는 안내
      expect(find.textContaining('설정에서 직접 허용'), findsOneWidget);

      await tester.tap(find.text('설정 열기'));
      await tester.pumpAndSettle();
      expect(reader.settingsOpened, 1);

      await tester.tap(find.text('권한 허용'));
      await tester.pumpAndSettle();
      expect(reader.requested, 2);
    });

    testWidgets('거부 상태에서 다시 허용하면 앱으로 넘어간다', (tester) async {
      final reader = FakeGalleryReader(
        accessState: GalleryAccess.denied,
        grantOnRequest: GalleryAccess.denied,
      );
      await _pumpApp(tester, reader);

      // 사용자가 설정에서 허용하고 돌아온 상황
      reader.accessState = GalleryAccess.authorized;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(Wordmark), findsOneWidget);
    });
  });

  group('디버그 OCR 측정', () {
    late Directory out;

    setUp(() => out = Directory.systemTemp.createTempSync('remine_export_'));
    tearDown(() => out.deleteSync(recursive: true));

    Future<FakeGalleryReader> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final reader = FakeGalleryReader(photos: fakePhotos(3));
      await tester.pumpWidget(
        MaterialApp(
          home: DebugOcrScreen(
            services: fakeServices(reader, exportTo: out),
            now: () => DateTime(2026, 10, 19, 12, 5, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return reader;
    }

    testWidgets('Screenshots 앨범이 먼저 열리고, 앨범을 바꿀 수 있다', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const ValueKey('album-shots')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('album-exp')));
      await tester.pumpAndSettle();
      expect(find.text('0장 선택 · 최근 300장까지'), findsOneWidget);
    });

    testWidgets('고른 사진만 OCR하고 JSON으로 내보낸다. 화면에는 원문이 없다', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const ValueKey('photo-p0')));
      await tester.tap(find.byKey(const ValueKey('photo-p2')));
      await tester.pump();
      expect(find.text('2장 선택 · 최근 300장까지'), findsOneWidget);

      await tester.tap(find.text('OCR 실행'));
      await _io(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('2장 완료'), findsOneWidget);
      expect(find.textContaining('글자 0'), findsNothing); // OCR 원문은 화면에 띄우지 않는다

      await tester.tap(find.text('JSON 내보내기'));
      await _io(tester);
      await tester.pumpAndSettle();

      final file = File('${out.path}/ocr-export-20261019-120509.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map;
      final items = (json['items'] as List).cast<Map>();
      expect(items.map((e) => e['fileName']), [
        'Screenshot_0.png',
        'Screenshot_2.png',
      ]);
      expect(items.first['charCount'], greaterThan(0));
    });

    testWidgets('아무것도 안 고르면 실행할 수 없고, 결과가 없으면 내보낼 수 없다', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('OCR 실행'), warnIfMissed: false);
      await tester.tap(find.text('JSON 내보내기'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(out.listSync(), isEmpty);
    });
  });
}
