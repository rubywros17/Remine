import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/older_progress.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/data/remote/remote_services.dart';
import 'package:remine/screens/older_range_screen.dart';
import 'package:remine/screens/older_shots_screen.dart';
import 'package:remine/screens/older_texts.dart';
import 'package:remine/widgets/pressable_scale.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

// ⑤ 예전 스크린샷: 진행률 · 오늘 몫 · 몫 0 · 다 끝남 · 스위치 저장 · 준비 중 · 서버 몫 갱신.
final _now = DateTime(2026, 11, 18, 12);

/// 하루 2장씩 900일 치(최신순).
final _photos = [
  for (var d = 0; d < 900; d++)
    for (var k = 0; k < 2; k++)
      GalleryPhoto(
        id: 'p${d * 2 + k}',
        fileName: 'Screenshot_${d * 2 + k}.png',
        takenAt: _now.subtract(Duration(days: d, hours: k)),
        modifiedAt: 1000 + d * 2 + k,
      ),
];

final _from = monthsAgo(_now, 12);
final _inYear = _photos.where((p) => !p.takenAt.isBefore(_from)).toList();

/// 1년 범위, 커서는 1년 범위의 [seen]번째 장(최신순).
InMemorySettingsStore _settings({int seen = 400, int? remaining = 120}) {
  final s = InMemorySettingsStore()
    ..olderKind = OlderRangeKind.year
    ..olderRange = ymd(_from)
    ..cursor = _inYear[seen - 1].position.encode();
  if (remaining != null) s.quota = (remaining: remaining, resetsAt: null);
  return s;
}

Future<void> _pump(
  WidgetTester tester,
  InMemorySettingsStore settings, {
  RemoteServices? remote,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: OlderShotsScreen(
        settings: settings,
        reader: FakeGalleryReader(photos: _photos),
        remote: remote,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('진행 카드: 범위 이름·진행률·"n / 전체장 · YYYY년 M월까지 봤어요", 오늘 몫 120 / 300', (
    tester,
  ) async {
    await _pump(tester, _settings());
    final total = _inYear.length;
    final seen = 400; // 커서 장까지 본 것, 그보다 오래된 것이 안 본 것
    final cursorAt = _inYear[399].takenAt;

    expect(find.text(OlderTexts.shotsTitle), findsOneWidget);
    expect(find.text('최근 1년'), findsOneWidget);
    expect(find.text('${(seen / total * 100).floor()}%'), findsOneWidget);
    expect(
      find.text(OlderTexts.progressLine(seen, total, cursorAt)),
      findsOneWidget,
    );
    expect(find.text('120 / 300', findRichText: true), findsOneWidget);
    expect(find.text(OlderTexts.quotaLabel), findsOneWidget);
    expect(find.text(OlderTexts.quotaAside), findsOneWidget);
    expect(find.text('최근 1년 · ${OlderTexts.shots(total)}'), findsOneWidget);
  });

  test('다 쓴 카드 안내: 한도보다 적게 남으면 "남은 N장을", 한도 이상이면 "다음 300장을"', () {
    expect(OlderTexts.quotaDoneBody(58, 300), '내일 앱을 열면 남은 58장을 이어서 정리해요.');
    for (final left in [300, 1000]) {
      expect(
        OlderTexts.quotaDoneBody(left, 300),
        '내일 앱을 열면 다음 300장을 이어서 정리해요.',
      );
    }
  });

  testWidgets('오늘 몫이 0이면 같은 레몬 카드에 "오늘 분량은 다 정리했어요", 남은 58장이면 셋째 줄 없음', (
    tester,
  ) async {
    await _pump(tester, _settings(seen: _inYear.length - 58, remaining: 0));

    expect(find.text('오늘 분량은 다 정리했어요'), findsOneWidget);
    expect(find.text('내일 앱을 열면 남은 58장을 이어서 정리해요.'), findsOneWidget);
    expect(
      find.text(OlderTexts.quotaDoneLeft(58)),
      findsNothing,
      reason: '안내와 겹친다',
    );
    expect(find.text(OlderTexts.quotaLabel), findsNothing);
    // 남은 횟수 카드와 같은 바탕·모양(레몬, 테두리 없음)
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('older-quota-done')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final d = box.decoration as BoxDecoration;
    expect(d.color, AppOlder.quotaBackground);
    expect(d.border, isNull);
    expect(d.borderRadius, BorderRadius.circular(AppOlder.optionRadius));
  });

  testWidgets('오늘 몫이 0이고 1000장 남았으면 "다음 300장을"과 셋째 줄 "남은 1,000장 · 약 4일"', (
    tester,
  ) async {
    final s = InMemorySettingsStore()
      ..olderKind = OlderRangeKind.all
      ..olderRange = olderRangeAll
      ..cursor = _photos[_photos.length - 1001].position.encode()
      ..quota = (remaining: 0, resetsAt: null);
    await _pump(tester, s);

    expect(find.text('내일 앱을 열면 다음 300장을 이어서 정리해요.'), findsOneWidget);
    expect(find.text('남은 1,000장 · 약 4일'), findsOneWidget);
  });

  testWidgets('다 끝나면 100%와 "예전 스크린샷을 모두 정리했어요"', (tester) async {
    final s = _settings()
      ..cursor = PhotoPosition(
        _from.subtract(const Duration(days: 1)),
        'x',
      ).encode();
    await _pump(tester, s);

    expect(find.text('100%'), findsOneWidget);
    expect(find.text(OlderTexts.allDone), findsOneWidget);
    expect(find.text(OlderTexts.quotaLabel), findsNothing);
    // 레몬 바탕·테두리 없음·검정 글씨(오늘 몫 카드와 같은 모양)
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('older-all-done')),
    );
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, AppColors.lemon);
    expect(deco.border, isNull);
    expect(
      tester.widget<Text>(find.text(OlderTexts.allDone)).style?.color,
      AppColors.ink,
    );
  });

  testWidgets('스위치 켜짐은 진한 셀라돈 트랙 + 흰 손잡이', (tester) async {
    await _pump(tester, _settings());
    final on = tester
        .widgetList<Switch>(find.byType(Switch))
        .where((w) => w.value);
    expect(on, isNotEmpty);
    for (final w in on) {
      expect(w.activeTrackColor, AppColors.celadonDeep);
      expect(w.activeThumbColor, AppColors.white);
    }
  });

  testWidgets('스위치를 누르면 바로 저장한다(이어서 정리하기·Wi-Fi에서만·충전 중일 때만)', (tester) async {
    final s = _settings();
    await _pump(tester, s);
    expect(s.enabled, isTrue);
    expect(s.wifiOnly, isTrue);
    expect(s.chargingOnly, isFalse);

    await tester.tap(find.text(OlderTexts.continueTitle));
    await tester.tap(find.text(OlderTexts.wifiOnly));
    await tester.tap(find.text(OlderTexts.chargingOnly));
    await tester.pumpAndSettle();

    expect(s.enabled, isFalse);
    expect(s.wifiOnly, isFalse);
    expect(s.chargingOnly, isTrue);
  });

  testWidgets('"더 빨리 정리하기"는 준비 중이라 누를 수 없다', (tester) async {
    await _pump(tester, _settings());
    expect(find.text(OlderTexts.faster), findsOneWidget);
    expect(find.text(OlderTexts.comingSoon), findsOneWidget);
    for (final type in [PressableScale, InkWell, GestureDetector]) {
      expect(
        find.ancestor(
          of: find.text(OlderTexts.faster),
          matching: find.byType(type),
        ),
        findsNothing,
        reason: '$type 없음',
      );
    }
    await tester.tap(find.text(OlderTexts.comingSoon), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(OlderShotsScreen), findsOneWidget);
  });

  testWidgets('분석 범위 줄을 누르면 범위 고르기(설정 모드)로', (tester) async {
    await _pump(tester, _settings());
    await tester.tap(find.text(OlderTexts.rangeRow));
    await tester.pumpAndSettle();
    expect(find.byType(OlderRangeScreen), findsOneWidget);
    expect(find.text(OlderTexts.confirm), findsOneWidget);
  });

  testWidgets('들어오면 서버에서 남은 몫을 다시 받아 보이고 저장한다', (tester) async {
    final rig = (await tester.runAsync(
      () => SyncRig.create(photos: const []),
    ))!;
    await rig.state.setDeviceId(7);
    rig.client.olderRemaining = 77;
    final s = _settings(remaining: 120);

    await _pump(tester, s, remote: rig.remote);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('77 / 300', findRichText: true), findsOneWidget);
    expect(rig.settings.quota?.remaining, 77, reason: '동기화 서비스의 설정에 저장');
  });
}
