import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/device_services.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/remine_store.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:remine/widgets/category_sheet.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/widgets/drawer_stage.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/widgets/small_widgets.dart';
import 'package:remine/widgets/wordmark.dart';

import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/photo_viewer_screen.dart';

import 'fake_device.dart';
import 'fake_remote.dart';

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
  FakeScreenshotRepository? repository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    RemineApp(
      repository: repository ?? FakeScreenshotRepository(now: () => _now),
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

    testWidgets('관심사 탭 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await tester.tap(find.byIcon(LucideIcons.star));
        await tester.pumpAndSettle();
        // 먼저 머릿속 지도: 다 그려진 뒤에도 [목록 보기]가 화면 안에 있어야 한다
        expect(find.text('목록 보기').hitTestable(), findsOneWidget);
        await tester.tap(find.text('목록 보기'));
        await tester.pumpAndSettle();
        expect(find.text('#니트가디건', skipOffstage: true), findsWidgets);
      });
      _expectClean('관심사 탭 $label', errors);
    });

    testWidgets('관심사 탭 빈 상태 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          repository: FakeScreenshotRepository(now: () => _now, seed: const []),
        );
        await tester.tap(find.byIcon(LucideIcons.star));
        await tester.pumpAndSettle();
        expect(find.text('아직 반복해서 캡처한 게 없어요'), findsOneWidget);
      });
      _expectClean('관심사 탭 빈 상태 $label', errors);
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

    testWidgets('관심사 태그 화면(형광펜 제목·큰 숫자·날짜별 막대) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건')); // 홈 관심사 카드 → 태그 화면
        expect(
          find.bySemanticsLabel(RegExp(r'^최근 \d+일 중 \d+일 캡처$')),
          findsOneWidget,
          reason: '태그 화면(날짜별 막대)이 아님',
        );
      });
      _expectClean('관심사 태그 화면 $label', errors);
    });

    testWidgets('상세 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건')); // 관심사 카드 → 카테고리(태그 선택)
        await _tap(tester, find.byType(Hero)); // 첫 타일 → 상세("더 보기" 버튼이 있는 항목)
        expect(
          find.textContaining('장 더 보기'),
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

    testWidgets('수정 시트 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건'));
        await _tap(tester, find.byType(Hero));
        // 아주 낮은 화면에서는 위쪽 끝으로 스크롤하면 상단 바에 가려지므로 가운데로 맞춘 뒤 누른다.
        // 카드 위 스티커에도 같은 이름이 있으므로 누르는 칩은 키로 찾는다.
        final chip = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('category-chip-'),
        );
        Scrollable.ensureVisible(
          tester.element(chip.first),
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        await tester.tap(chip.first);
        await tester.pumpAndSettle(); // 카테고리 칩 → 시트
        expect(find.text('어느 서랍에 넣을까요?'), findsOneWidget);
      });
      _expectClean('수정 시트 $label', errors);
    });

    testWidgets('수정 시트 · 문화생활 + 세 자리 장수(선택 칸) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = FakeScreenshotRepository(
          now: () => _now,
          seed: [
            for (var i = 0; i < 999; i++)
              ScreenshotItem(
                id: i + 1,
                localAssetId: 'e$i',
                takenAt: _now,
                category: Category.entertainment,
                tags: const [],
              ),
          ],
        );
        await tester.pumpWidget(
          RemineScope(
            store: RemineStore(repo, now: () => _now),
            child: const MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: CategorySheet(
                    current: Category.entertainment,
                    autoCategory: Category.entertainment,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final name = find.text(Category.entertainment.label);
        final tile = find.ancestor(
          of: name,
          matching: find.byType(AnimatedContainer),
        );
        final badge = find.byKey(const ValueKey('count-badge-ENTERTAINMENT'));
        // 글자·아이콘은 수정 전 크기 그대로(줄이지 않는다), 비율 축소 없음.
        expect(
          tester.widget<Text>(name).style!.fontSize,
          CategoryTileSize.nameFontSize,
        );
        expect(find.byType(FittedBox), findsNothing);
        // 320×480·1.3배는 여백을 다 줄여도 모자라 배지만 숨긴다.
        final narrow = realFonts && size == const Size(320, 480) && scale > 1;
        if (narrow) {
          expect(badge, findsNothing, reason: '320×480·1.3배는 배지를 숨긴다');
        }
        // 이름은 한 줄이고, 이름(과 배지)은 칸 안에 있다(잘리지 않음).
        // 15px 글자 한 줄 높이는 두 줄(15 × 배율 × 2)보다 낮다.
        expect(tester.getSize(name).height, lessThan(15 * scale * 2));
        final box = tester.getRect(tile);
        expect(tester.getRect(name).left, greaterThanOrEqualTo(box.left));
        expect(tester.getRect(name).right, lessThanOrEqualTo(box.right + 0.5));
        if (badge.evaluate().isNotEmpty) {
          expect(
            find.descendant(of: badge, matching: find.text('999')),
            findsOneWidget,
          );
          expect(
            tester.getRect(badge).right,
            lessThanOrEqualTo(box.right + 0.5),
            reason: '배지가 칸 밖으로 ${tester.getRect(badge).right - box.right}px',
          );
        }
      });
      _expectClean('수정 시트 문화생활 999 $label', errors);
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

    testWidgets('이미지 분석 동의 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          device: fakeServices(
            FakeGalleryReader(),
            settings: InMemorySettingsStore(null),
          ),
        );
        expect(find.text('동의할래요'), findsOneWidget);
        expect(find.text('안 할래요'), findsOneWidget);
      });
      _expectClean('동의 $label', errors);
    });

    testWidgets('설정 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          device: fakeServices(FakeGalleryReader()),
        );
        await _tap(tester, find.byIcon(LucideIcons.settings));
        expect(find.byType(Switch), findsOneWidget, reason: '설정 화면이 아님');
      });
      _expectClean('설정 $label', errors);
    });

    testWidgets('정리 탭(휴지통 줄) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          device: fakeServices(FakeGalleryReader()),
        );
        await _tap(tester, find.text('정리'));
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        expect(find.text('0장'), findsOneWidget);
      });
      _expectClean('정리 $label', errors);
    });

    testWidgets('휴지통(전체 선택 + 하단 [복구]·[삭제 N장]) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final store = InMemoryTrashStore();
        for (var i = 0; i < 12; i++) {
          await store.add(
            TrashedShot(
              assetId: 't$i',
              category: Category.values[i % Category.values.length],
              takenAt: _now,
              trashedAt: _now.add(Duration(minutes: i)),
              onServer: false,
            ),
          );
        }
        await _pump(
          tester,
          size,
          scale,
          device: fakeServices(FakeGalleryReader(), trash: store),
        );
        await _tap(tester, find.byIcon(LucideIcons.settings));
        await _tap(tester, find.text('휴지통'));
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        await _tap(tester, find.text('전체 선택'));
        expect(find.text('선택 해제'), findsOneWidget);
        expect(find.text('삭제 12장'), findsOneWidget);
      });
      _expectClean('휴지통 $label', errors);
    });

    testWidgets('첫 분석 · 실제 진행(큰 숫자·예상 시간·홈 버튼) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var clock = DateTime(2026, 10, 21, 12);
        final status = SyncStatus(now: () => clock);
        status.begin(300);
        clock = clock.add(const Duration(minutes: 30));
        status.advance(299); // 999에 가까운 자릿수·몇 시간짜리 예상 시간 문구까지 그려 본다
        for (final c in Category.values) {
          for (var i = 0; i < 40; i++) {
            status.count(c);
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: AnalysisScreen(status: status, onHome: () {}),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400)); // 진행 막대가 계속 움직인다
        expect(find.text('홈에서 먼저 볼래요'), findsOneWidget);
        // 시작 직후(예상 시간 계산 중)와 실행 전(0/0)도 그려 본다.
        final fresh = SyncStatus()..begin(300);
        await tester.pumpWidget(
          MaterialApp(
            home: AnalysisScreen(status: fresh, onHome: () {}),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(etaPendingText), findsOneWidget);
        // 서버 응답을 기다리는 중(움직이는 막대 + 안내 문구). 막대가 계속 움직이므로 settle 대신 시간을 흘려보낸다.
        final waiting = SyncStatus()..begin(300);
        waiting.setWaiting(20);
        await tester.pumpWidget(
          MaterialApp(
            home: AnalysisScreen(status: waiting, onHome: () {}),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('20장을 분류하는 중이에요'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });
      _expectClean('첫 분석 실제 진행 $label', errors);
    });

    testWidgets('첫 분석 · 완료 요약·대기 묶음·카드 비행(칸 99장) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final status = SyncStatus()..begin(999);
        status.advance(999);
        // 가장 긴 카테고리 이름(문화생활)과 여러 자릿수 개수까지 그려 본다.
        for (final c in Category.values) {
          for (var i = 0; i < 99; i++) {
            status.count(c);
          }
        }
        status.count(Category.entertainment); // 강조 줄이 가장 긴 "문화생활이에요"가 되게
        status.finish();
        Future<void> show(SyncStatus st, {FakeGalleryReader? reader}) async {
          await tester.pumpWidget(
            MaterialApp(
              home: DeviceScope(
                services: fakeServices(reader ?? FakeGalleryReader()),
                child: AnalysisScreen(status: st, onHome: () {}),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
        }

        await show(status);
        expect(find.text('홈에서 둘러보기'), findsOneWidget);
        // 요약은 미리 잡아 둔 자리 안에 다 들어간다(넘치면 잘린다).
        final slot = tester.getRect(
          find.byKey(const ValueKey('summary-slot-box')),
        );
        final summary = tester.getRect(find.byType(AnalysisSummary));
        expect(
          summary.bottom,
          lessThanOrEqualTo(slot.bottom + 0.5),
          reason: '요약이 자리보다 ${summary.bottom - slot.bottom}px 길다',
        );
        // 아직 한 장도 분류되지 않은 완료(새 캡처 없음)와 연결 실패 안내.
        await show(SyncStatus()..finish());
        expect(find.text('새로 꺼낼 캡처가 없어요'), findsWidgets);
        await show(SyncStatus()..finish(issue: SyncIssue.offline));
        expect(find.textContaining('서버에 연결하지 못했어요'), findsOneWidget);
        // 진행 중 + 대기 묶음과 카드가 쌓이고 날아가는 상태(칸마다 몇 장씩 들어간다).
        final partial = SyncStatus()..begin(300);
        partial.setWaiting(16, assetIds: ['w0', 'w1', 'w2']);
        await tester.pumpWidget(
          MaterialApp(
            home: DeviceScope(
              services: fakeServices(FakeGalleryReader()),
              child: AnalysisScreen(status: partial, onHome: () {}),
            ),
          ),
        );
        for (var i = 0; i < 28; i++) {
          partial.count(
            Category.values[i % Category.values.length],
            assetId: 'x$i',
          );
        }
        partial.advance(28);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.byType(DrawerFlightCard), findsWidgets);
        expect(find.text('홈에서 먼저 볼래요'), findsOneWidget);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      });
      _expectClean('첫 분석 완료 상태 $label', errors);
    });

    testWidgets('전체 화면 보기(확대 전·확대 후·사진 없음) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        Future<void> show(String assetId) async {
          await tester.pumpWidget(
            MaterialApp(
              home: DeviceScope(
                services: fakeServices(FakeGalleryReader()),
                child: PhotoViewerScreen(assetId: assetId, seed: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show('a1');
        expect(
          find.byKey(const ValueKey('photo-viewer-close')),
          findsOneWidget,
        );
        final viewer = find.byKey(const ValueKey('photo-viewer'));
        final c = tester.getCenter(viewer);
        final g1 = await tester.startGesture(c - const Offset(10, 0));
        final g2 = await tester.startGesture(c + const Offset(10, 0));
        await g1.moveBy(const Offset(-40, 0));
        await g2.moveBy(const Offset(40, 0));
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();
        await show('missing');
        expect(find.text('사진이 없어요'), findsOneWidget);
      });
      _expectClean('전체 화면 보기 $label', errors);
    });

    testWidgets('홈 · 서버 연결 안내 띠(오프라인·일부 실패) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // 임시 폴더를 만드는 실제 파일 I/O라 위젯 테스트의 가짜 시계 밖(runAsync)에서 준비한다.
        final rig = (await tester.runAsync(
          () => SyncRig.create(
            photos: fakePhotos(1),
            texts: {'p0': '글자'},
            client: RecordingClient()..throwOnSend = const SocketException('x'),
          ),
        ))!;
        await rig.state.setFirstSyncDone(); // 첫 분석 화면을 건너뛰고 바로 홈
        await tester.pumpWidget(
          RemineApp(
            repository: FakeScreenshotRepository(now: () => _now),
            now: () => _now,
            device: fakeServices(rig.reader, remote: rig.remote),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('서버에 연결하지 못했어요'), findsOneWidget);
        // 일부 실패 안내(가장 긴 문구)도 그려 본다.
        rig.status.finish(issue: SyncIssue.partial, failedCount: 288);
        await tester.pumpAndSettle();
        expect(find.textContaining('288장은 다음에'), findsOneWidget);
      });
      _expectClean('홈 연결 안내 띠 $label', errors);
    });

    testWidgets('분석 제외 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final services = fakeServices(FakeGalleryReader());
        final verdicts = services.capture.verdicts;
        // 사유가 여러 개 겹친 가장 긴 라벨까지 그려 본다.
        await verdicts.save(
          StoredVerdict.of(
            const LocalVerdict(
              route: LocalRoute.deviceOnly,
              category: Category.etc,
              hidden: true,
              reasons: ['SSN', 'CARD', 'ACCOUNT', 'OTP', 'PASSWORD'],
            ),
            assetId: 'a1',
            takenAt: _now,
            modifiedAt: 1,
            now: _now,
          ),
        );
        for (var i = 0; i < 12; i++) {
          await verdicts.save(
            StoredVerdict.of(
              judgeByApp('Screenshot_20261019_120000_KakaoBank.jpg')!,
              assetId: 'b$i',
              takenAt: _now,
              modifiedAt: 1,
              now: _now,
            ),
          );
        }
        await _pump(tester, size, scale, device: services);
        await _tap(tester, find.textContaining('분석 제외'));
        expect(
          find.textContaining('서버로 보내지 않고'),
          findsOneWidget,
          reason: '분석 제외 화면이 아님',
        );
      });
      _expectClean('분석 제외 $label', errors);
    });

    testWidgets('디버그 OCR 처리 중(999 / 999 + 진행 막대) · $label', (tester) async {
      final done = Completer<void>();
      addTearDown(() {
        if (!done.isCompleted) done.complete();
      });
      final errors = await _errorsDuring(() async {
        final reader = _AllPhotosReader(fakePhotos(999));
        final base = fakeServices(reader);
        final services = DeviceServices(
          reader: reader,
          capture: _StallingCapture(base.capture, done.future),
          settings: base.settings,
          trash: base.trash,
          exportDir: base.exportDir,
        );
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(home: DebugOcrScreen(services: services)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('전체 선택'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text('OCR 실행'),
        ); // 아주 작은 화면에서는 패널 안을 스크롤해야 보인다
        await tester.pumpAndSettle();
        await tester.tap(find.text('OCR 실행'), warnIfMissed: false);
        await tester.pump();
        await tester.pump();
        expect(find.text('처리 중 999 / 999'), findsOneWidget);
        expect(find.byKey(const ValueKey('ocr-progress')), findsOneWidget);
        expect(find.text('멈추기'), findsOneWidget);
        done.complete(); // 끝나면 원래 버튼들이 돌아온다
        await tester.pumpAndSettle();
        expect(find.text('멈추기'), findsNothing);
      });
      _expectClean('처리 중 $label', errors);
    });

    testWidgets('디버그 앱 이름별 개수 시트 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final reader = FakeGalleryReader(
          photos: [
            for (var i = 0; i < 30; i++)
              GalleryPhoto(
                id: 'p$i',
                fileName:
                    'Screenshot_20261019_1200${i.toString().padLeft(2, '0')}_Very Long Application Name Number $i.jpg',
                takenAt: _now,
                modifiedAt: i,
              ),
          ],
        );
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(home: DebugOcrScreen(services: fakeServices(reader))),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('앱 이름별 개수'));
        await tester.tap(find.text('앱 이름별 개수'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.textContaining('전체 30장'), findsOneWidget);
      });
      _expectClean('앱 이름별 개수 $label', errors);
    });

    testWidgets('첫 분석 · $label', (tester) async {
      final errors = await _errorsDuring(
        () => _pump(tester, size, scale, start: 'analysis'),
      );
      _expectClean('첫 분석 $label', errors);
    });
  }
}

/// 앨범의 사진을 장수 제한 없이 돌려주는 갤러리(999장 화면을 만들려는 테스트용).
class _AllPhotosReader extends FakeGalleryReader {
  _AllPhotosReader(List<GalleryPhoto> all) : super(photos: all);

  @override
  Future<List<GalleryPhoto>> recent(String albumId, {int limit = 300}) async =>
      photos;
}

/// 전부 처리했다고 알린 직후 [release]될 때까지 끝나지 않는 서비스(처리 중 화면을 붙잡아 둔다).
class _StallingCapture extends DeviceCaptureService {
  _StallingCapture(DeviceCaptureService base, this.release)
    : super(
        reader: base.reader,
        ocr: base.ocr,
        store: base.store,
        temp: base.temp,
        verdicts: base.verdicts,
      );

  final Future<void> release;

  @override
  Future<OcrRun> run(
    List<GalleryPhoto> photos, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(photos.length, photos.length);
    await release;
    return const OcrRun(records: [], failed: 0, skipped: 0);
  }
}
