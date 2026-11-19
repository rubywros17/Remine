import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('오늘 몫이 0이면 오늘 몫 카드 대신 "오늘 몫은 다 정리했어요"와 남은 장수·날수', (tester) async {
    await _pump(tester, _settings(remaining: 0));
    final left = _inYear.length - 400;

    expect(find.text(OlderTexts.quotaDoneTitle), findsOneWidget);
    expect(find.text(OlderTexts.quotaDoneBody), findsOneWidget);
    expect(find.text(OlderTexts.quotaDoneLeft(left)), findsOneWidget);
    expect(find.text(OlderTexts.quotaLabel), findsNothing);
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
