import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
import 'package:remine/widgets/interest_brain_map.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/widgets/peek_preview.dart';
import 'package:remine/data/fake_data.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/widgets/home_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:remine/widgets/small_widgets.dart';
import 'package:remine/widgets/wordmark.dart';

import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/screens/analysis_screen.dart';
import 'package:remine/screens/photo_viewer_screen.dart';
import 'package:remine/screens/older_range_screen.dart';
import 'package:remine/screens/older_shots_screen.dart';
import 'package:remine/screens/older_texts.dart';

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

/// 관심사 목록 두 섹션: 크롬 데모(잊은 4 · 요즘 3) + 긴 태그 요즘 관심사 4개(각 3장). 다 펼치면 카드 11개.
List<ScreenshotItem> _twoSectionInterests() {
  final demo = buildDemoScreenshots(_now);
  var id = demo.length;
  return [
    ...demo,
    for (final (i, tag) in const [
      '데스크테리어',
      '프로필사진',
      '홈카페인테리어',
      '캘리그라피',
    ].indexed)
      for (var k = 0; k < 3; k++)
        ScreenshotItem(
          id: ++id,
          localAssetId: 'longtag$id',
          takenAt: _now.subtract(Duration(days: 2 + i, hours: k)),
          category: Category.etc,
          tags: [tag],
          summary: '캡처 $id',
        ),
  ];
}

/// 긴 키워드 관심사 7개(많이 캡처한 순 = 9, 8, … 3장). 첫 키워드가 가장 길다.
List<ScreenshotItem> _sevenLongInterests() => _sevenInterests(const [
  '겨울캠핑장비추천리스트총정리',
  '니트가디건코디',
  '제주도한달살기숙소',
  '홈카페레시피',
  '아이폰케이스',
  '주말브런치맛집',
  '전시회일정정리',
]);

/// 보통 길이 키워드 관심사 7개.
List<ScreenshotItem> _sevenUsualInterests() => _sevenInterests(const [
  '필기구',
  '캠핑',
  '다이어리꾸미기',
  '뜨개질',
  '제주여행',
  '홈카페',
  '니트가디건',
]);

/// 관심사 7개(많이 캡처한 순 = 9, 8, … 3장).
/// 마지막 둘(서로 이어진 캡처 포함)은 40일 넘게 안 찍어 잊고 있었던 관심사 → 잊은 2 + 요즘 5.
List<ScreenshotItem> _sevenInterests(List<String> tags) {
  var id = 0;
  return [
    for (final (i, tag) in tags.indexed)
      for (var k = 0; k < 9 - i; k++)
        ScreenshotItem(
          id: ++id,
          localAssetId: 'long$id',
          takenAt: _now.subtract(
            Duration(days: k % 5 + (i >= 5 ? 40 : 0), hours: k),
          ),
          category: Category.values[i % Category.values.length],
          // 앞 키워드와 한 장씩 함께 → 연결선
          tags: [tag, if (k == 0 && i > 0) tags[i - 1]],
          summary: '캡처 $id',
        ),
  ];
}

void _expectClean(String where, List<String> errors) {
  expect(errors, isEmpty, reason: '$where\n  ${errors.toSet().join('\n  ')}');
}

/// 예전 스크린샷 노란 카드: 라벨은 단어 중간에서 끊기지 않고(실제 폰트면 1.0배 한 줄 · 1.3배 두 줄까지),
/// 안내는 카드 오른쪽 안쪽 끝에 붙는다.
void _expectQuotaCard(
  WidgetTester tester,
  double scale,
  String where, {
  required bool realFonts,
}) {
  final p = tester.renderObject<RenderParagraph>(
    find.text(OlderTexts.quotaLabel),
  );
  final text = OlderTexts.quotaLabel;
  // 커서 높이(y)가 바뀌는 글자 = 새 줄의 첫 글자. 그 앞이나 그 글자가 띄어쓰기여야 단어 경계에서 바뀐 것이다.
  double y(int i) => p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
  var lines = 1;
  for (var i = 1; i < text.length; i++) {
    if (y(i) <= y(i - 1)) continue;
    lines++;
    expect(
      text[i] == ' ' || text[i - 1] == ' ',
      isTrue,
      reason: '$where 라벨이 단어 중간에서 줄바꿈',
    );
  }
  if (realFonts) {
    expect(
      lines,
      lessThanOrEqualTo(scale > 1 ? 2 : 1),
      reason: '$where 라벨 줄 수',
    );
  }
  final aside = find.byKey(const ValueKey('older-quota-aside'));
  final card = find
      .ancestor(of: aside, matching: find.byType(DecoratedBox))
      .first;
  expect(
    tester.getTopRight(aside).dx,
    moreOrLessEquals(tester.getTopRight(card).dx - AppSpacing.s16),
    reason: '$where 안내가 카드 오른쪽 끝에 붙지 않음',
  );
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
      // 실제 폰트, 기본 글자: 360×800·412×915 홈은 스크롤 없이 서랍 알약까지 탭바 위에 다 보인다(홈 카드 184).
      if (realFonts &&
          scale == 1.0 &&
          (size == const Size(360, 800) || size == const Size(412, 915))) {
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.maxScrollExtent, 0, reason: '홈이 스크롤된다');
        expect(
          tester.getRect(find.byType(Wrap).last).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(AppTabBar)).top),
          reason: '서랍 알약이 탭바에 가린다',
        );
        expect(
          tester.getSize(find.byType(InterestCard)).height,
          AppInterestCard.homeMinHeight,
        );
      }
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
        // 아주 작은 화면에서는 섹션 머리·점선 안내 아래라 화면 밖일 수 있다(목록에는 있다).
        expect(find.text('#니트가디건', skipOffstage: false), findsWidgets);
      });
      _expectClean('관심사 탭 $label', errors);
    });

    testWidgets('관심사 지도 긴 키워드 7개 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          repository: FakeScreenshotRepository(
            now: () => _now,
            seed: _sevenLongInterests(),
          ),
        );
        await tester.tap(find.byIcon(LucideIcons.star));
        await tester.pumpAndSettle();
        expect(find.text('목록 보기').hitTestable(), findsOneWidget);
        final paint = find
            .descendant(
              of: find.byType(InterestBrainMap),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .map((e) => e.widget as CustomPaint)
            .firstWhere((c) => c.painter is BrainPainter);
        final chips = (paint.painter! as BrainPainter).chips;
        final canvas = (Offset.zero & tester.getSize(find.byWidget(paint)))
            .inflate(0.5);
        // 아주 긴 키워드는 육각형 자리에 다 못 앉으면 뒤 순위 칩부터 빠진다(목록에는 그대로).
        if (size.width >= 360 && scale == 1.0) {
          expect(chips, isNotEmpty);
        }
        for (final (i, a) in chips.indexed) {
          expect(
            canvas.contains(a.rect.topLeft) &&
                canvas.contains(a.rect.bottomRight),
            isTrue,
            reason: '${a.node.interest.tag} 칩이 캔버스 밖',
          );
          for (final b in chips.skip(i + 1)) {
            expect(
              a.rect.inflate(4.9).overlaps(b.rect.inflate(4.9)),
              isFalse,
              reason: '${a.node.interest.tag} ↔ ${b.node.interest.tag} 10px 미만',
            );
          }
        }
      });
      _expectClean('관심사 지도 긴 키워드 $label', errors);
    });

    // 보통 폰(360×800·412×915, 글자 1.0·1.3배): 보통 길이 칩 7개가 서로 10px 이상·캔버스 안, 뇌 윤곽에서 1.0배는 8px·1.3배는 4px 이상
    // (1.3배에서 7개가 안 되면 1개 이상·10px·캔버스 안),
    // 애니메이션 끄기면 첫 프레임이 마지막 상태.
    if (size == const Size(360, 800) || size == const Size(412, 915)) {
      testWidgets('관심사 지도 칩 7개 뇌 안 · 애니메이션 끄기 · $label', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final errors = await _errorsDuring(() async {
          await _pump(
            tester,
            size,
            scale,
            repository: FakeScreenshotRepository(
              now: () => _now,
              seed: _sevenUsualInterests(),
            ),
          );
          await tester.tap(find.byIcon(LucideIcons.star));
          await tester.pump();
          final paint = find
              .descendant(
                of: find.byType(InterestBrainMap),
                matching: find.byType(CustomPaint),
              )
              .evaluate()
              .map((e) => e.widget as CustomPaint)
              .firstWhere((c) => c.painter is BrainPainter);
          final painter = paint.painter! as BrainPainter;
          // 시계 길이는 고른 관심사 수 기준이라, 칩이 빠지면 그려진 칩의 끝보다 길 수 있다.
          expect(
            painter.ms,
            greaterThanOrEqualTo(
              brainTotalMs(
                painter.chips.length,
                brainLinks([for (final c in painter.chips) c.node]).length,
              ),
            ),
            reason: '애니메이션 끄기면 바로 끝 상태',
          );
          expect(tester.hasRunningAnimations, isFalse);
          final chips = painter.chips;
          // 글자 1.3배는 윤곽 여백을 4px까지 줄여도 7개가 안 되면 뒤 순위부터 빠진다 → 1개 이상·10px·캔버스 안만 본다.
          final full = scale == 1.0 || chips.length == 7;
          if (full) {
            expect(chips, hasLength(7));
            expect(
              chips.where((c) => c.node.interest.forgotten),
              hasLength(2),
              reason: '잊은 2 + 요즘 5',
            );
          } else {
            expect(chips, isNotEmpty);
          }
          final canvasSize = tester.getSize(find.byWidget(paint));
          final canvas = (Offset.zero & canvasSize).inflate(0.5);
          for (final (i, c) in chips.indexed) {
            // 윤곽 여백: 글자 1.0배는 8px, 1.3배는 칩 7개를 지키려고 4px까지 허용.
            if (full) {
              final margin = scale == 1.0
                  ? AppBrain.chipBrainMinMargin
                  : AppBrain.chipBrainLooseMargin;
              expect(
                chipFitsBrain(canvasSize, c.rect, margin),
                isTrue,
                reason:
                    '${c.node.interest.tag} 칩이 뇌 윤곽 ${margin}px 안쪽이 아님 ${c.rect}',
              );
            }
            expect(
              canvas.contains(c.rect.topLeft) &&
                  canvas.contains(c.rect.bottomRight),
              isTrue,
              reason: '${c.node.interest.tag} 칩이 캔버스 밖',
            );
            for (final d in chips.skip(i + 1)) {
              expect(
                c.rect.inflate(4.9).overlaps(d.rect.inflate(4.9)),
                isFalse,
                reason:
                    '${c.node.interest.tag} ↔ ${d.node.interest.tag} 10px 미만',
              );
            }
          }
        });
        _expectClean('관심사 지도 뇌 안 $label', errors);
      });
    }

    testWidgets('정리 탭 벤토·한 번에 보기 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        final trash = InMemoryTrashStore();
        await trash.add(
          TrashedShot(
            assetId: 'gone',
            category: Category.etc,
            takenAt: _now,
            trashedAt: _now,
            onServer: false,
          ),
        );
        final reader = FakeGalleryReader();
        for (var i = 1; i <= 30; i++) {
          reader.sizes['fake-${i.toString().padLeft(3, '0')}'] = 900000000;
        }
        await _pump(
          tester,
          size,
          scale,
          device: fakeServices(reader, trash: trash),
        );
        await tester.tap(find.byIcon(LucideIcons.broom));
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        expect(find.text('지워도 될 만한 스크린샷을 모아 드릴게요'), findsOneWidget);
        await _tap(tester, find.text('한 번에 보기 →'));
        expect(
          find.byType(BackButtonCircle),
          findsOneWidget,
          reason: '묶음 화면으로 이동하지 못함',
        );
      });
      _expectClean('정리 탭 $label', errors);
    });

    testWidgets('관심사 목록 두 섹션·더 보기·검색 · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(
          tester,
          size,
          scale,
          repository: FakeScreenshotRepository(
            now: () => _now,
            seed: _twoSectionInterests(),
          ),
        );
        await tester.tap(find.byIcon(LucideIcons.star));
        await tester.pumpAndSettle();
        await tester.tap(find.text('목록 보기'));
        await tester.pumpAndSettle();
        // 큰 폰 기본 글자: 잊은 카드 2개 + 요즘 카드 2개가 첫 화면(탭바 위)에 보인다
        if (size == const Size(412, 915) && scale == 1.0) {
          final tabTop = tester.getTopLeft(find.byType(AppTabBar)).dy;
          final cards = find.byType(InterestCard);
          expect(
            tester.getBottomLeft(cards.at(3)).dy,
            lessThanOrEqualTo(tabTop),
            reason: '네 번째 카드(요즘 2번째)가 첫 화면 밖',
          );
          // 실제 폰트에서 시안 높이: 잊은 카드 약 140, 요즘 카드는 그 80%
          if (realFonts) {
            final forgotten = tester.getSize(cards.at(0)).height;
            final recent = tester.getSize(cards.at(2)).height;
            expect(forgotten, closeTo(AppInterestCard.minHeight, 2));
            expect(recent / forgotten, closeTo(0.8, 0.03));
          }
        }
        await _tap(tester, find.textContaining('잊고 있었던 관심사 2개 더 보기'));
        await _tap(tester, find.textContaining('요즘 모으는 중 4개 더 보기'));
        // 카드 11개: 맨 아래로 → 맨 위로 버튼(화면 안, 눌러서 이동)
        final jump = find.byKey(const ValueKey('scroll-jump'));
        expect(jump.hitTestable(), findsOneWidget, reason: '내려온 상태라 보인다');
        final screen = Offset.zero & size;
        expect(screen.contains(tester.getRect(jump).bottomRight), isTrue);
        // 펼친 직후 위치에 따라 아래·위 어느 쪽이든: 아래면 맨 아래로 가서 위로 바뀌고, 위면 맨 위로 가서 숨는다.
        final up = find.byIcon(Icons.keyboard_double_arrow_up);
        if (up.evaluate().isEmpty) {
          await tester.tap(jump);
          await tester.pumpAndSettle();
          expect(up, findsOneWidget, reason: '맨 아래에서는 위 화살표');
        }
        await tester.tap(jump);
        await tester.pumpAndSettle();
        expect(jump.hitTestable(), findsNothing, reason: '맨 위에서는 숨는다');
        await _tap(tester, find.text('접기 ↑'));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(LucideIcons.search));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '홈카페');
        await tester.pumpAndSettle();
        // 잊은 #홈카페 + 요즘 #홈카페인테리어(작은 화면에서는 아래 카드가 화면 밖)
        // (홈 탭의 관심사 카드도 화면 밖에 있어 카드 수 대신 태그로 센다)
        for (final tag in ['#홈카페', '#홈카페인테리어']) {
          expect(find.text(tag, skipOffstage: false), findsOneWidget);
        }
        expect(find.text('#코바늘도안'), findsNothing);
      });
      _expectClean('관심사 목록 두 섹션 $label', errors);
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

    testWidgets('관심사 태그 화면(형광펜 제목·큰 숫자·월별 막대) · $label', (tester) async {
      final errors = await _errorsDuring(() async {
        await _pump(tester, size, scale);
        await _tap(tester, find.text('#니트가디건')); // 홈 관심사 카드 → 태그 화면
        expect(
          find.bySemanticsLabel(RegExp(r'^최근 \d+개월 중 \d+개월 캡처$')),
          findsOneWidget,
          reason: '태그 화면(월별 막대)이 아님',
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
          find.byKey(const ValueKey('more-button')),
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
        // 휴지통은 정리 탭의 휴지통 타일에서 연다(설정에는 없다).
        await tester.tap(find.byIcon(LucideIcons.broom));
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        await _tap(tester, find.text('휴지통'));
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        await _tap(tester, find.text('전체 선택'));
        expect(find.text('선택 해제'), findsOneWidget);
        expect(find.text('삭제 12장'), findsOneWidget);
      });
      _expectClean('휴지통 $label', errors);
    });

    // 예전 스크린샷 정리: ① 범위 고르기(첫 실행·직접 고른 뒤·설정 모드) · ② 기간 시트 · ⑤ 상세(보통·몫 0·다 끝남).
    if (size == const Size(360, 800) || size == const Size(412, 915)) {
      testWidgets('예전 스크린샷 범위 고르기·기간 시트·상세 · $label', (tester) async {
        final errors = await _errorsDuring(() async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          // 하루 2장씩 900일 치(전부 1,800장, 1년 약 730장)
          final reader = FakeGalleryReader(
            photos: [
              for (var i = 0; i < 1800; i++)
                GalleryPhoto(
                  id: 'o$i',
                  fileName: 'Screenshot_$i.png',
                  takenAt: _now.subtract(Duration(hours: 12 * i)),
                  modifiedAt: i,
                ),
            ],
          );
          Widget range({bool fromSettings = false}) => MaterialApp(
            home: OlderRangeScreen(
              // 설정 진입은 오늘 남은 몫이 있어 안내 박스가 3줄인 경우까지 본다.
              settings: InMemorySettingsStore()
                ..quota = fromSettings
                    ? (remaining: 300, resetsAt: null)
                    : null,
              reader: reader,
              now: () => _now,
              fromSettings: fromSettings,
              onDone: fromSettings ? null : () {},
            ),
          );

          await tester.pumpWidget(range());
          await tester.pumpAndSettle();
          expect(find.text(OlderTexts.rangeTitle), findsOneWidget);
          await _tap(tester, find.text(OlderTexts.custom));
          expect(find.text(OlderTexts.sheetTitle), findsOneWidget);
          await tester.tap(find.text(OlderTexts.confirm));
          await tester.pumpAndSettle();
          expect(find.textContaining('직접: '), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(range(fromSettings: true));
          await tester.pumpAndSettle();
          expect(find.text(OlderTexts.confirm), findsOneWidget);

          final cursor = reader.photos[400].position.encode();
          for (final (remaining, done) in [
            (120, false),
            (0, false),
            (120, true),
          ]) {
            final settings = InMemorySettingsStore()
              ..olderKind = OlderRangeKind.year
              ..olderRange = ymd(DateTime(_now.year - 1, _now.month, _now.day))
              ..cursor = done
                  ? PhotoPosition(DateTime(2000), 'x').encode()
                  : cursor
              ..quota = (remaining: remaining, resetsAt: null);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              MaterialApp(
                home: OlderShotsScreen(settings: settings, reader: reader),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(
                done
                    ? OlderTexts.allDone
                    : remaining == 0
                    ? OlderTexts.quotaDoneTitle
                    : OlderTexts.quotaLabel,
              ),
              findsOneWidget,
            );
            if (remaining > 0 && !done) {
              _expectQuotaCard(tester, scale, label, realFonts: realFonts);
            }
            if (remaining == 0) {
              // 다 쓴 카드도 남은 횟수 카드와 같은 레몬 바탕
              final box = tester.widget<DecoratedBox>(
                find.descendant(
                  of: find.byKey(const ValueKey('older-quota-done')),
                  matching: find.byType(DecoratedBox),
                ),
              );
              expect(
                (box.decoration as BoxDecoration).color,
                AppOlder.quotaBackground,
                reason: label,
              );
            }
            // 맨 아래 "더 빨리 정리하기"까지 내려 그려 본다
            await _tap(tester, find.text(OlderTexts.faster));
          }
        });
        _expectClean('예전 스크린샷 화면 $label', errors);
      });
    }

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
        await verdicts.save(
          StoredVerdict.of(
            const LocalVerdict(
              route: LocalRoute.deviceOnly,
              category: Category.etc,
              hidden: true,
              reasons: [ReasonCode.appOwn],
            ),
            assetId: 'own1',
            takenAt: _now,
            modifiedAt: 1,
            now: _now,
          ),
        );
        await _pump(tester, size, scale, device: services);
        await _tap(tester, find.textContaining('분석 제외'));
        expect(
          find.textContaining('서버로 보내지 않고'),
          findsOneWidget,
          reason: '분석 제외 화면이 아님',
        );
        // 꾹 눌러 크게 보기(열린 상태)를 그려 본다. 선택 바가 칸을 가리기 전에(아주 작은 화면).
        final peek = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('excluded-own1'))),
        );
        await tester.pump(AppTidy.peekPress + const Duration(milliseconds: 20));
        await tester.pump();
        await tester.pump(AppTidy.peekOpen);
        expect(find.byType(PeekPreview), findsOneWidget);
        await peek.up();
        await tester.pumpAndSettle();
        // 두 장 골라 하단 [휴지통으로 2장] 바까지 그려 본다.
        // 맨 위 두 장(최신순: 마지막에 저장한 own1, 그다음 b11).
        await _tap(tester, find.byKey(const ValueKey('excluded-own1')));
        await _tap(tester, find.byKey(const ValueKey('excluded-b11')));
        // 240×320처럼 아주 작은 화면은 첫 선택으로 바가 올라와 두 번째 칸을 가릴 수 있어 바가 떴는지만 본다.
        expect(find.textContaining('휴지통으로'), findsOneWidget);
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
