import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/settings_store.dart';
import 'package:remine/screens/consent_screen.dart';
import 'package:remine/screens/debug_ocr_screen.dart';
import 'package:remine/screens/excluded_screen.dart';
import 'package:remine/screens/settings_screen.dart';

import 'support/fake_device.dart';

void main() {
  group('이미지 분석 동의', () {
    Future<void> pumpGate(WidgetTester tester, SettingsStore s) =>
        tester.pumpWidget(
          MaterialApp(
            home: ConsentGate(settings: s, child: const Text('앱 본문')),
          ),
        );

    testWidgets('동의하면 저장하고 앱으로 넘어간다', (tester) async {
      final s = InMemorySettingsStore();
      await pumpGate(tester, s);
      await tester.pumpAndSettle();
      expect(find.text(consentTitle), findsOneWidget);
      await tester.tap(find.text('동의할래요'));
      await tester.pumpAndSettle();
      expect(await s.imageConsent(), isTrue);
      expect(find.text('앱 본문'), findsOneWidget);
    });

    testWidgets('거부하면 false로 저장한다', (tester) async {
      final s = InMemorySettingsStore();
      await pumpGate(tester, s);
      await tester.pumpAndSettle();
      await tester.tap(find.text('안 할래요'));
      await tester.pumpAndSettle();
      expect(await s.imageConsent(), isFalse);
      expect(find.text('앱 본문'), findsOneWidget);
    });

    testWidgets('선택하지 않고 나가면(뒤로 가기) 거부로 처리한다', (tester) async {
      final s = InMemorySettingsStore();
      await pumpGate(tester, s);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await s.imageConsent(), isFalse);
      expect(find.text('앱 본문'), findsOneWidget);
    });

    testWidgets('이미 고른 적이 있으면 묻지 않는다', (tester) async {
      await pumpGate(tester, InMemorySettingsStore(true));
      await tester.pumpAndSettle();
      expect(find.text(consentTitle), findsNothing);
      expect(find.text('앱 본문'), findsOneWidget);
    });

    test('문구는 해요체이고 서버 저장 안 함·민감/전화번호 제외·끄기를 알린다', () {
      final text = [consentBody, ...consentPoints].join(' ');
      expect(text, contains('저장하지 않아요'));
      expect(text, contains('전화번호'));
      expect(text, contains('설정에서 언제든 끌 수 있어요'));
      for (final sentence in [consentBody, ...consentPoints]) {
        expect(sentence, endsWith('요.'));
      }
    });
  });

  testWidgets('설정에서 동의를 켜고 끌 수 있다', (tester) async {
    final s = InMemorySettingsStore(true);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(settings: s)));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(await s.imageConsent(), isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(await s.imageConsent(), isTrue);
  });

  testWidgets('분석 제외 화면은 숨긴 캡처를 사유 이름과 함께 보여 준다', (tester) async {
    final verdicts = InMemoryLocalVerdictStore();
    final now = DateTime(2026, 10, 19);
    Future<void> put(String id, LocalVerdict v) => verdicts.save(
      StoredVerdict.of(
        v,
        assetId: id,
        takenAt: now,
        modifiedAt: 1,
        now: now,
      ),
    );
    await put('a', judgeByText('카드 4111 1111 1111 1111'));
    await put('b', judgeByApp('Screenshot_20261019_120000_KakaoBank.jpg')!);
    // 노출 대상(메신저)은 여기에 나오지 않는다.
    await put('c', judgeByApp('Screenshot_20261019_120000_KakaoTalk.jpg')!);
    await tester.pumpWidget(
      MaterialApp(
        home: ExcludedScreen(verdicts: verdicts, reader: FakeGalleryReader()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('카드번호'), findsOneWidget);
    expect(find.text('금융 앱'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('디버그 화면의 앱 이름별 개수: 앱 이름·장수·종류만 보인다', (tester) async {
    GalleryPhoto photo(int i, String name) => GalleryPhoto(
      id: 'p$i',
      fileName: name,
      takenAt: DateTime(2026),
      modifiedAt: i,
    );
    final reader = FakeGalleryReader(
      photos: [
        photo(0, 'Screenshot_20261019_120000_KakaoTalk.jpg'),
        photo(1, 'Screenshot_20261019_120001_KakaoTalk.jpg'),
        photo(2, 'Screenshot_20261019_120002_Chrome.jpg'),
      ],
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: DebugOcrScreen(services: fakeServices(reader))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 이름별 개수'));
    await tester.pumpAndSettle();
    expect(find.text('앱 이름별 개수 · 전체 3장'), findsOneWidget);
    expect(find.text('KakaoTalk'), findsOneWidget);
    expect(find.text('2장 · 메신저 → 대화'), findsOneWidget);
    expect(find.text('1장 · 목록에 없음'), findsOneWidget);
  });
}
