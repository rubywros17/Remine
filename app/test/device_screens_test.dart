import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/widgets/wordmark.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

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

    // 실기기 버그: 갤럭시에 이름이 Screenshots인 앨범이 둘(DCIM/Screenshots, Pictures/Screenshots) 있으면
    // 칩 키를 이름으로 만들어 "Duplicate keys found" 오류가 났다. 키·선택은 앨범 id 기준이어야 한다.
    group('이름이 같은 앨범이 둘 이상', () {
      FakeGalleryReader twinReader() => FakeGalleryReader(
        albums: const [
          GalleryAlbum(
            id: 'pic',
            name: 'Screenshots',
            count: 500,
            relativePath: 'Pictures/Screenshots/',
          ),
          GalleryAlbum(
            id: 'dcim',
            name: 'Screenshots',
            count: 40,
            relativePath: 'DCIM/Screenshots/',
          ),
          GalleryAlbum(id: 'exp', name: 'RemineExperiment', count: 43),
        ],
        photos: fakePhotos(350),
      );

      Future<FakeGalleryReader> open(WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final reader = twinReader();
        await tester.pumpWidget(
          MaterialApp(home: DebugOcrScreen(services: fakeServices(reader))),
        );
        await tester.pumpAndSettle();
        return reader;
      }

      testWidgets('오류 없이 열리고, DCIM/Screenshots가 기본으로 열린다', (tester) async {
        final reader = await open(tester);

        expect(tester.takeException(), isNull);
        expect(reader.requestedAlbums, ['dcim']);
        expect(find.byKey(const ValueKey('album-dcim')), findsOneWidget);
        expect(find.byKey(const ValueKey('album-pic')), findsOneWidget);
      });

      testWidgets('같은 이름 칩은 경로로 구분되고, 다른 이름 칩은 그대로다', (tester) async {
        await open(tester);

        expect(find.textContaining('DCIM/Screenshots/'), findsOneWidget);
        expect(find.textContaining('Pictures/Screenshots/'), findsOneWidget);
        expect(find.text('RemineExperiment 43'), findsOneWidget);
      });

      testWidgets('칩을 고르면 그 id의 앨범만 불러오고, 자동으로 합치지 않는다', (tester) async {
        final reader = await open(tester);

        await tester.ensureVisible(find.byKey(const ValueKey('album-pic')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('album-pic')));
        await tester.pumpAndSettle();

        expect(reader.requestedAlbums, ['dcim', 'pic']);
      });

      testWidgets('한 앨범에서 최대 300장만 읽는다', (tester) async {
        final reader = await open(tester);

        expect(reader.limits, [300]);
        expect(find.byType(GestureDetector), findsWidgets);
        await tester.tap(find.text('전체 선택'));
        await tester.pump();
        expect(find.text('300장 선택 · 최근 300장까지'), findsOneWidget);
      });
    });

    testWidgets('하단 패널 배경은 화면 전체 폭이고 아래 시스템 영역(제스처 바)까지 채운다', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      final reader = FakeGalleryReader(photos: fakePhotos(3));
      await tester.pumpWidget(
        MaterialApp(
          home: DebugOcrScreen(services: fakeServices(reader, exportTo: out)),
        ),
      );
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byKey(const ValueKey('bottom-panel')));
      expect(panel.left, 0);
      expect(panel.right, 390);
      expect(panel.bottom, 844); // 하단 시스템 영역까지
      // 버튼은 시스템 영역 위에 있다(내용만 안쪽 여백)
      expect(
        tester.getRect(find.text('OCR 실행')).bottom,
        lessThanOrEqualTo(844 - 34),
      );
    });

    testWidgets(
      '선택 표시: 사진이 0.86배로 줄고 15%만 어두워지며, 바깥에 3px 딥 셀라돈 테두리가 생기고 체크 원이 테두리 모서리에 붙는다',
      (tester) async {
        await pumpScreen(tester);
        final tile = find.byKey(const ValueKey('photo-p0'));
        final photo = find.descendant(
          of: tile,
          matching: find.byType(ClipRRect),
        );
        final before = tester.getRect(photo);
        Finder dim() => find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == AppColors.selectionDim,
          ),
        );
        Finder whiteRing() => find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border?.top.color ==
                    AppColors.white,
          ),
        );

        // 미선택: 흰 테두리 빈 원 + 얇은 그림자, 어둡게 없음
        expect(whiteRing(), findsOneWidget);
        final ring =
            tester.widget<DecoratedBox>(whiteRing()).decoration
                as BoxDecoration;
        expect(ring.boxShadow, isNotEmpty);
        expect(dim(), findsNothing);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.descendant(
                  of: tile,
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity,
          0,
        ); // 테두리는 선택했을 때만 보인다

        await tester.tap(tile);
        await tester.pumpAndSettle();

        final after = tester.getRect(photo);
        expect(after.width, closeTo(before.width * 0.86, 0.5));
        // 부동소수 반올림 때문에 정확히 같지 않을 수 있다(위치에 따라 끝자리가 달라짐).
        expect(after.center.dx, closeTo(before.center.dx, 0.01));
        expect(after.center.dy, closeTo(before.center.dy, 0.01));
        expect(AppColors.selectionDim.a, closeTo(0.15, 0.01));
        expect(dim(), findsOneWidget);
        // 바깥쪽 3px 딥 셀라돈 테두리: 줄어든 사진을 감싸고, 반경은 줄어든 반경 + 3
        final borderBox = find.descendant(
          of: tile,
          matching: find.byKey(const ValueKey('thumb-border')),
        );
        final border = tester.getRect(borderBox);
        expect(border.left, closeTo(after.left - 3, 0.5));
        expect(border.right, closeTo(after.right + 3, 0.5));
        expect(border.top, closeTo(after.top - 3, 0.5));
        final deco =
            tester.widget<DecoratedBox>(borderBox).decoration as BoxDecoration;
        expect(deco.border!.top.color, AppColors.celadonDeep);
        expect(deco.border!.top.width, 3);
        expect(deco.borderRadius, BorderRadius.circular(12 * 0.86 + 3));
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.ancestor(
                  of: borderBox,
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity,
          1,
        );
        // 체크 원은 테두리까지 포함한 우상단 모서리 안쪽 6px에 있다
        final check = tester.getRect(
          find.descendant(of: tile, matching: find.byIcon(LucideIcons.check)),
        );
        expect(check.center.dx, closeTo(border.right - 6 - 11, 1));
        expect(check.center.dy, closeTo(border.top + 6 + 11, 1));
      },
    );

    testWidgets('애니메이션 줄이기: 축소가 바로 적용된다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScreen(tester);
      final tile = find.byKey(const ValueKey('photo-p0'));
      final photo = find.descendant(of: tile, matching: find.byType(ClipRRect));
      final before = tester.getRect(photo);

      await tester.tap(tile);
      await tester.pump(); // 프레임 한 번이면 끝난다(추가 시간 진행 없음)
      await tester.pump();

      expect(tester.getRect(photo).width, closeTo(before.width * 0.86, 0.5));
      // 테두리도 즉시 나타난다
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(of: tile, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        1,
      );
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('아무것도 안 고르면 실행할 수 없고, 결과가 없으면 내보낼 수 없다', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('OCR 실행'), warnIfMissed: false);
      await tester.tap(find.text('JSON 내보내기'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(out.listSync(), isEmpty);
    });
  });
  group('디버그 측정 화면의 서버 기기 id', () {
    Future<void> pump(WidgetTester tester, DeviceServices services) async {
      await tester.pumpWidget(
        MaterialApp(home: DebugOcrScreen(services: services)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('등록된 id를 보여 주고 길게 누르면 복사한다', (tester) async {
      final rig = await tester.runAsync(() => SyncRig.create(photos: const []));
      await rig!.state.setDeviceId(42);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pump(tester, fakeServices(FakeGalleryReader(), remote: rig.remote));
      expect(find.text('서버 기기 id: 42'), findsOneWidget);

      await tester.longPress(find.text('서버 기기 id: 42'));
      await tester.pumpAndSettle();
      expect(copied, '42');
    });

    testWidgets('등록 전이면 없다고 알려 준다', (tester) async {
      final rig = await tester.runAsync(() => SyncRig.create(photos: const []));
      await pump(
        tester,
        fakeServices(FakeGalleryReader(), remote: rig!.remote),
      );
      expect(find.text('서버 기기 id: 없음(아직 등록 전)'), findsOneWidget);
    });

    testWidgets('서버 연동이 없으면 그렇다고 알려 준다', (tester) async {
      await pump(tester, fakeServices(FakeGalleryReader()));
      expect(find.textContaining('서버 연동 꺼짐'), findsOneWidget);
    });
  });
}
