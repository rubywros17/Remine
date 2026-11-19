import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/older_progress.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/screens/older_range_screen.dart';
import 'package:remine/screens/older_texts.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

// ① 어디까지 정리할까요? · ② 기간 직접 고르기 시트 · RangeGate · 고른 범위가 첫 분석 장수를 줄이는지.
final _now = DateTime(2026, 11, 18, 12);

/// 하루 2장씩 [days]일 치(최신순). 1년 = 약 730장.
List<GalleryPhoto> _daily(int days) => [
  for (var d = 0; d < days; d++)
    for (var k = 0; k < 2; k++)
      GalleryPhoto(
        id: 'p${d * 2 + k}',
        fileName: 'Screenshot_${d * 2 + k}.png',
        takenAt: _now.subtract(Duration(days: d, hours: k)),
        modifiedAt: 1000 + d * 2 + k,
      ),
];

int _since(List<GalleryPhoto> photos, DateTime from) =>
    photos.where((p) => !p.takenAt.isBefore(from)).length;

Future<FakeGalleryReader> _pump(
  WidgetTester tester, {
  InMemorySettingsStore? settings,
  bool fromSettings = false,
  VoidCallback? onDone,
  List<GalleryPhoto>? photos,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final reader = FakeGalleryReader(photos: photos ?? _daily(900));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => fromSettings
            ? Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => OlderRangeScreen(
                          settings: settings ?? InMemorySettingsStore(),
                          reader: reader,
                          fromSettings: true,
                          now: () => _now,
                        ),
                      ),
                    ),
                    child: const Text('OPEN'),
                  ),
                ),
              )
            : OlderRangeScreen(
                settings: settings ?? InMemorySettingsStore(),
                reader: reader,
                onDone: onDone,
                now: () => _now,
              ),
      ),
    ),
  );
  if (fromSettings) {
    await tester.tap(find.text('OPEN'));
  }
  await tester.pumpAndSettle();
  return reader;
}

Color? _cardColor(WidgetTester tester, String key) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (box.decoration! as BoxDecoration).color;
}

void main() {
  group('olderDays: 오늘 몫 + 내일부터 하루 300장', () {
    test('예전 1000장: 오늘 0장이면 내일부터 4일, 56장이면 오늘 포함 5일, 300장이면 오늘 포함 4일', () {
      expect(olderDays(1000, today: 0), 4);
      expect(olderDays(1000, today: 56), 5);
      expect(olderDays(1000, today: 300), 4);
    });

    test('0장이면 0일, 오늘 몫 안에 끝나면 1일', () {
      expect(olderDays(0, today: 300), 0);
      expect(olderDays(40, today: 56), 1);
    });

    test('첫 실행(범위 전체, 오늘 = 최신 300장)은 ⌈n/300⌉과 같다', () {
      for (final n in [1, 300, 301, 730, 900, 1800]) {
        expect(olderDays(n, today: 300), olderDaysFor(n), reason: '$n장');
      }
    });

    test('olderTodayLeft: 저장값 없으면 0, 초기화 시각 전이면 남은 값, 지났으면 하루 한도', () {
      expect(olderTodayLeft(null, _now), 0);
      final tomorrow = DateTime(2026, 11, 19);
      expect(olderTodayLeft((remaining: 56, resetsAt: tomorrow), _now), 56);
      expect(olderTodayLeft((remaining: 0, resetsAt: null), _now), 0);
      final today0 = DateTime(2026, 11, 18);
      expect(
        olderTodayLeft((remaining: 0, resetsAt: today0), _now),
        olderDailyLimit,
        reason: '어제 저장된 0 + 초기화 시각 지남 → 300',
      );
    });
  });

  testWidgets('첫 실행 안내: 오늘은 최신 300장을 먼저, 나머지는 내일부터 하루 300장씩', (tester) async {
    await _pump(tester);
    expect(
      find.text(
        '오늘은 최신 300장을 먼저 정리해요.\n나머지는 내일부터 앱을 열 때마다 하루 300장씩 이어서 분석해요.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('오늘 최신 300장부터'), findsNWidgets(2), reason: '최근 1년·전부');
  });

  group('설정에서 다시 고를 때는 최신 300장을 빼고 오늘 남은 몫으로 센다', () {
    // 하루 2장 900일: 최근 1년 = 730장 → 예전 430장, 전부 1800장 → 예전 1500장.
    Future<void> pumpWith(
      WidgetTester tester,
      ({int remaining, DateTime? resetsAt})? quota,
    ) async {
      final settings = InMemorySettingsStore()..quota = quota;
      await _pump(tester, settings: settings, fromSettings: true);
    }

    testWidgets('오늘 56장 남음 → "오늘 56장 더", 오늘 포함 일수', (tester) async {
      await pumpWith(tester, (remaining: 56, resetsAt: DateTime(2026, 11, 19)));
      expect(find.text('오늘 56장 더'), findsNWidgets(2));
      expect(
        find.text(OlderTexts.days(olderDays(430, today: 56))),
        findsOneWidget,
      );
      expect(
        find.text(OlderTexts.days(olderDays(1500, today: 56))),
        findsOneWidget,
      );
      expect(
        find.text(
          '오늘은 56장 더 정리할 수 있어요.\n하루에 300장씩 정리해요.\n나머지는 앱을 열 때마다 이어서 분석해요.',
          findRichText: true,
        ),
        findsOneWidget,
        reason: '설정 진입은 지금 안내 그대로',
      );
    });

    testWidgets('"최근 300장" 카드는 이미 끝났으니 "완료 / 정리했어요", "오늘 바로" 배지 없음', (
      tester,
    ) async {
      await pumpWith(tester, null);
      final recent = find.byKey(const ValueKey('older-option-recent'));
      Finder inRecent(String t) =>
          find.descendant(of: recent, matching: find.text(t));
      expect(inRecent('완료'), findsOneWidget);
      expect(inRecent('분석했어요'), findsOneWidget);
      expect(inRecent(OlderTexts.todayDone), findsNothing);
      expect(inRecent(OlderTexts.minutes(4)), findsNothing);
      expect(find.text(OlderTexts.recent300Badge), findsNothing);
    });

    testWidgets('오늘 0장 → "내일부터", 내일부터 센 일수', (tester) async {
      await pumpWith(tester, (remaining: 0, resetsAt: DateTime(2026, 11, 19)));
      expect(find.text('내일부터'), findsNWidgets(2));
      expect(
        find.textContaining('더 정리할 수 있어요', findRichText: true),
        findsNothing,
        reason: '오늘 남은 몫이 없으면 안내 첫 줄 없음',
      );
      expect(find.text(OlderTexts.days(olderDaysFor(430))), findsOneWidget);
    });

    testWidgets('어제 저장된 0 + 초기화 시각 지남 → "오늘 300장 더"', (tester) async {
      await pumpWith(tester, (remaining: 0, resetsAt: DateTime(2026, 11, 18)));
      expect(find.text('오늘 300장 더'), findsNWidgets(2));
      expect(
        find.text(OlderTexts.days(olderDays(430, today: 300))),
        findsOneWidget,
      );
    });
  });

  testWidgets('제목·설명·선택지 장수, 기본은 "최근 1년", 선택 카드는 차콜·나머지는 바탕색', (tester) async {
    final photos = _daily(900);
    await _pump(tester, photos: photos);
    final year = _since(photos, monthsAgo(_now, 12));

    expect(find.text(OlderTexts.rangeTitle), findsOneWidget);
    expect(find.textContaining('총 ${_fmt(photos.length)}장'), findsOneWidget);
    expect(find.text(OlderTexts.shots(year)), findsOneWidget);
    expect(find.text(OlderTexts.days(olderDaysFor(year))), findsOneWidget);
    expect(find.text(OlderTexts.shots(photos.length)), findsOneWidget);
    expect(
      find.text(OlderTexts.minutes(4)),
      findsOneWidget,
      reason: '300장 약 4분',
    );
    expect(
      find.text(OlderTexts.recentMonths(5)),
      findsOneWidget,
      reason: '하루 2장 → 300장은 약 5달 치',
    );
    expect(find.text('오늘 바로'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(find.text(OlderTexts.custom), findsOneWidget);
    expect(find.text('정리 시작'), findsOneWidget);

    expect(_cardColor(tester, 'older-option-year'), AppColors.darkGray);
    expect(_cardColor(tester, 'older-option-recent'), AppColors.background);
    expect(_cardColor(tester, 'older-option-all'), AppColors.background);

    await tester.tap(find.byKey(const ValueKey('older-option-all')));
    await tester.pumpAndSettle();
    expect(_cardColor(tester, 'older-option-all'), AppColors.darkGray);
    expect(_cardColor(tester, 'older-option-year'), AppColors.background);
  });

  testWidgets('화면 리더: 선택지는 이름·장수·날수·선택됨을 한 번에 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    final photos = _daily(900);
    await _pump(tester, photos: photos);
    final year = _since(photos, monthsAgo(_now, 12));

    expect(
      find.bySemanticsLabel(
        '최근 1년, ${_fmt(year)}장, 오늘 최신 300장부터 ${olderDaysFor(year)}일, 선택됨',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('older-option-year'))),
      isSemantics(isSelected: true, isButton: true),
    );
    handle.dispose();
  });

  testWidgets('장수를 세는 동안은 숫자 자리가 비어 있고 버튼이 눌리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reader = _SlowReader();
    await tester.pumpWidget(
      MaterialApp(
        home: OlderRangeScreen(
          settings: InMemorySettingsStore(),
          reader: reader,
          now: () => _now,
          onDone: () => fail('세기 전에는 저장하지 않는다'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(OlderTexts.days(1)), findsNothing);
    expect(find.textContaining('총 …장'), findsOneWidget);
    await tester.tap(find.text('정리 시작'));
    await tester.pump();
  });

  testWidgets('기간 직접 고르기: 슬라이더 9달이 기본, 1달로 바꿔 정하면 직접 카드가 선택된다', (tester) async {
    final handle = tester.ensureSemantics();
    final photos = _daily(900);
    final settings = InMemorySettingsStore();
    var done = false;
    await _pump(
      tester,
      photos: photos,
      settings: settings,
      onDone: () => done = true,
    );

    await tester.tap(find.text(OlderTexts.custom));
    await tester.pumpAndSettle();
    expect(find.text(OlderTexts.sheetTitle), findsOneWidget);
    final nine = _since(photos, monthsAgo(_now, 9));
    expect(
      find.bySemanticsLabel(RegExp('9달 전부터 ${_fmt(nine)}장')),
      findsWidgets,
      reason: '슬라이더 화면 리더 문구',
    );
    expect(
      find.text('2026년 2월부터 · 오늘 포함 약 ${olderDaysFor(nine)}일'),
      findsOneWidget,
    );
    final bold = tester.widget<Text>(find.text('9달'));
    expect(bold.style?.fontWeight, FontWeight.w700, reason: '고른 눈금만 굵게');

    tester.widget<Slider>(find.byType(Slider)).onChanged!(0); // 1달
    await tester.pumpAndSettle();
    final one = _since(photos, monthsAgo(_now, 1));
    expect(find.text('${_fmt(one)}장', findRichText: true), findsOneWidget);
    await tester.tap(find.text(OlderTexts.confirm));
    await tester.pumpAndSettle();

    expect(find.text(OlderTexts.sheetTitle), findsNothing);
    final label = OlderTexts.customChosen(monthsAgo(_now, 1), one);
    expect(find.text(label), findsOneWidget);
    expect(_cardColor(tester, 'older-option-custom'), AppColors.darkGray);
    expect(_cardColor(tester, 'older-option-year'), AppColors.background);

    await tester.tap(find.text('정리 시작'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(settings.olderKind, OlderRangeKind.custom);
    expect(settings.olderRange, '2026-10-18');
    handle.dispose();
  });

  testWidgets('슬라이더 채움은 레몬(모두 정리했어요 카드 바탕과 같은 색), 바탕 트랙은 연회색', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(OlderTexts.custom));
    await tester.pumpAndSettle();
    final theme = SliderTheme.of(tester.element(find.byType(Slider)));
    expect(
      theme.activeTrackColor,
      AppColors.lemon,
      reason: '모두 정리했어요 카드와 같은 레몬',
    );
    expect(theme.inactiveTrackColor, AppColors.border);
  });

  testWidgets('슬라이더 "전부"로 정하면 전부 카드가 선택된다', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(OlderTexts.custom));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
    await tester.pumpAndSettle();
    await tester.tap(find.text(OlderTexts.confirm));
    await tester.pumpAndSettle();
    expect(_cardColor(tester, 'older-option-all'), AppColors.darkGray);
  });

  testWidgets(
    '정리 시작: 고른 범위를 저장하고 첫 분석으로 넘어간다(1년 = 지금 기준 1년 전, 최근 300장 = 예전 정리 안 함)',
    (tester) async {
      final settings = InMemorySettingsStore();
      var done = 0;
      await _pump(tester, settings: settings, onDone: () => done++);

      await tester.tap(find.text('정리 시작'));
      await tester.pumpAndSettle();
      expect(done, 1);
      expect(settings.olderKind, OlderRangeKind.year);
      expect(settings.olderRange, '2025-11-18');

      final recent = InMemorySettingsStore();
      await tester.pumpWidget(const SizedBox()); // 새 화면으로(상태를 이어 쓰지 않게)
      await _pump(tester, settings: recent, onDone: () => done++);
      await tester.tap(find.byKey(const ValueKey('older-option-recent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('정리 시작'));
      await tester.pumpAndSettle();
      expect(recent.olderRange, olderRangeNone);
      expect(olderRangeStart(recent.olderRange).enabled, isFalse);
    },
  );

  testWidgets('설정에서 들어오면 버튼이 "이 범위로 정하기"이고, 저장한 뒤 뒤로 간다(저장된 범위가 처음 선택)', (
    tester,
  ) async {
    final settings = InMemorySettingsStore()
      ..olderKind = OlderRangeKind.all
      ..olderRange = olderRangeAll;
    await _pump(tester, settings: settings, fromSettings: true);

    expect(find.text('정리 시작'), findsNothing);
    expect(find.text(OlderTexts.confirm), findsOneWidget);
    expect(_cardColor(tester, 'older-option-all'), AppColors.darkGray);

    await tester.tap(find.byKey(const ValueKey('older-option-year')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OlderTexts.confirm));
    await tester.pumpAndSettle();
    expect(find.byType(OlderRangeScreen), findsNothing, reason: '저장 후 뒤로');
    expect(settings.olderKind, OlderRangeKind.year);
  });

  group('RangeGate', () {
    Future<SyncRig> rig(WidgetTester tester) async =>
        (await tester.runAsync(() => SyncRig.create(photos: _daily(10))))!;

    Widget gate(SyncRig r) => MaterialApp(
      home: RangeGate(
        remote: r.remote,
        settings: r.settings,
        reader: r.reader,
        child: const Text('첫 분석'),
      ),
    );

    testWidgets('첫 실행에 범위를 안 골랐으면 먼저 묻고, 고르면 첫 분석으로', (tester) async {
      final r = await rig(tester);
      await tester.pumpWidget(gate(r));
      await tester.pumpAndSettle();
      expect(find.text(OlderTexts.rangeTitle), findsOneWidget);
      expect(find.text('첫 분석'), findsNothing);

      await tester.tap(find.text('정리 시작'));
      await tester.pumpAndSettle();
      expect(find.text('첫 분석'), findsOneWidget);
      expect(r.settings.olderKind, OlderRangeKind.year);
    });

    testWidgets('이미 첫 분석을 마친 기기(업데이트)는 묻지 않는다', (tester) async {
      final r = await rig(tester);
      await r.state.setFirstSyncDone();
      await tester.pumpWidget(gate(r));
      await tester.pumpAndSettle();
      expect(find.text('첫 분석'), findsOneWidget);
    });

    testWidgets('범위를 이미 골랐으면 묻지 않는다', (tester) async {
      final r = await rig(tester);
      r.settings.olderRange = olderRangeNone;
      await tester.pumpWidget(gate(r));
      await tester.pumpAndSettle();
      expect(find.text('첫 분석'), findsOneWidget);
    });
  });

  group('범위를 안 골랐거나 "최근 300장"이면 범위 규칙 없이 최신 300장을 다 보낸다', () {
    // 3일에 1장씩 310장(약 2년 반 치): 1년 범위였다면 1년보다 오래된 장이 빠졌을 것
    final photos = [
      for (var i = 0; i < 310; i++)
        GalleryPhoto(
          id: 'p$i',
          fileName: 'Screenshot_$i.png',
          takenAt: DateTime(2026, 10, 21, 12).subtract(Duration(days: 3 * i)),
          modifiedAt: 1000 + i,
        ),
    ];

    Future<void> expectRecent300(SyncRig rig) async {
      await rig.sync.run();
      final sent = [
        for (final r in rig.client.analyzeCalls)
          ...RegExp(r'"localAssetId":"([^"]+)"')
              .allMatches(r.utf8Text)
              .map((m) => m.group(1)!),
      ];
      expect(rig.status.total, 300);
      expect(sent, hasLength(300));
      expect(sent, contains('p299'), reason: '약 2년 반 전 캡처도 보낸다');
      expect(sent, isNot(contains('p300')), reason: '최신 300장까지만');
    }

    Future<SyncRig> rig() => SyncRig.create(
      photos: photos,
      texts: {for (final p in photos) p.id: '글자 ${p.id}'},
      consent: false,
    );

    test('아직 안 고름(null)', () async {
      final r = await rig();
      expect(r.settings.olderRange, isNull);
      await expectRecent300(r);
    });

    test('최근 300장(none)', () async {
      final r = await rig();
      await r.settings.setOlderRange(OlderRangeKind.recent300);
      expect(r.settings.olderRange, olderRangeNone);
      await expectRecent300(r);
    });
  });

  test('고른 범위보다 오래된 캡처는 첫 분석에서도 보내지 않는다(총 장수 = min(300, 범위 장수))', () async {
    final photos = [
      for (var i = 0; i < 40; i++)
        GalleryPhoto(
          id: 'p$i',
          fileName: 'Screenshot_$i.png',
          takenAt: DateTime(2026, 10, 21, 12).subtract(Duration(days: i)),
          modifiedAt: 1000 + i,
        ),
    ];
    final rig = await SyncRig.create(
      photos: photos,
      texts: {for (final p in photos) p.id: '글자 ${p.id}'},
      consent: false,
    );
    await rig.settings.setOlderRange(
      OlderRangeKind.custom,
      from: DateTime(2026, 10, 12),
    );

    await rig.sync.run();

    expect(rig.status.total, 10, reason: '10/12~10/21의 10장만');
    expect(rig.client.analyzeCalls.single.utf8Text, isNot(contains('"p10"')));
  });
}

String _fmt(int n) => OlderTexts.shots(n).replaceAll('장', '');

/// 장수를 끝내 돌려주지 않는 갤러리(세는 중 상태 확인용).
class _SlowReader extends FakeGalleryReader {
  @override
  Future<int> count(String albumId, {DateTime? from, DateTime? before}) =>
      Completer<int>().future;
}
