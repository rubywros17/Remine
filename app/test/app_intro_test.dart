import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/screens/shell_screen.dart';
import 'package:remine/widgets/app_intro.dart';

final _overlay = find.byKey(AppIntro.overlayKey);

/// 아래 화면이 인트로 동안 새로 만들어지지 않는지 센다.
class _Home extends StatefulWidget {
  const _Home();
  static int built = 0;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    _Home.built++;
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('HOME')));
}

/// 햅틱 호출 수. SystemChannels.platform을 가로챈다.
List<String> _platformCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (c) async {
      calls.add('${c.method} ${c.arguments}');
      return null;
    },
  );
  return calls;
}

int _haptics(List<String> calls) =>
    calls.where((c) => c.startsWith('HapticFeedback.vibrate')).length;

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      home: const _Home(),
      builder: (context, child) => AppIntro(child: child!),
    ),
  );
}

void main() {
  setUp(() => _Home.built = 0);

  testWidgets('끝까지 재생하면 덮개가 빠지고 남은 애니메이션이 없다', (tester) async {
    final calls = _platformCalls(tester);
    await _pump(tester);
    expect(_overlay, findsOneWidget);
    expect(find.text('HOME').hitTestable(), findsNothing); // 덮여 있다

    await tester.pump(const Duration(milliseconds: 400));
    expect(_haptics(calls), 1); // 찰칵

    await tester.pump(AppMotion.introTotal);
    expect(_overlay, findsNothing);
    expect(find.text('HOME').hitTestable(), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_haptics(calls), 1);
    expect(_Home.built, 1); // 아래 화면은 처음 만든 그대로
  });

  testWidgets('탭하면 바로 원으로 열기로 건너뛴다', (tester) async {
    final calls = _platformCalls(tester);
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(_overlay);
    await tester.pump();
    // 열리는 동안은 아래 화면을 만질 수 있다
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('HOME').hitTestable(), findsOneWidget);

    await tester.pump(
      const Duration(
        milliseconds: AppMotion.introTotalMs - AppMotion.introRevealStartMs,
      ),
    );
    expect(_overlay, findsNothing); // 전체 3.1초보다 훨씬 먼저 끝난다
    expect(_haptics(calls), 0); // 찰칵 전에 건너뛰었다
    expect(_Home.built, 1);
  });

  testWidgets('애니메이션 줄이기가 켜져 있으면 인트로 없이 바로 화면', (tester) async {
    final calls = _platformCalls(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await _pump(tester);
    expect(_overlay, findsNothing);
    expect(find.text('HOME').hitTestable(), findsOneWidget);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_haptics(calls), 0);
  });

  testWidgets('앱: 인트로 뒤 홈, 다시 포그라운드로 와도 안 나온다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RemineApp(intro: true));
    expect(_overlay, findsOneWidget);
    expect(find.byType(ShellScreen), findsOneWidget); // 처음부터 아래에 만들어져 있다

    await tester.pump(AppMotion.introTotal);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_overlay, findsNothing);

    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(_overlay, findsNothing);
    expect(find.byType(ShellScreen), findsOneWidget);
  });

  testWidgets('인트로 동안 상태바·내비바가 인트로 바탕색', (tester) async {
    await _pump(tester);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: _overlay,
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    expect(region.value.statusBarColor, IntroColors.background);
    expect(region.value.systemNavigationBarColor, IntroColors.background);
  });

  // 완성 상태(로고 유지 구간)가 앱 아이콘과 겹치는지: 아이콘 1024px 원본에서 잰 값과 기하 비교(허용 오차 1dp).
  // 값은 tokens.dart와 일부러 따로 적었다 — 토큰을 잘못 고치면 여기서 깨진다.
  for (final size in const [Size(360, 800), Size(412, 915)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('완성 상태가 아이콘 비율과 같다 ${size.width.toInt()}×'
          '${size.height.toInt()} 글자 $scale배', (tester) async {
        await _pump(tester, size: size, textScale: scale);
        await tester.pump(const Duration(milliseconds: 2000));

        final frame = (size.width * 0.4).clamp(0, 180).toDouble();
        final k = frame / 724;
        final origin = size.center(Offset.zero) - Offset(512 * k, 512 * k);
        Rect icon(double l, double t, double w, double h) =>
            Rect.fromLTWH(origin.dx + l * k, origin.dy + t * k, w * k, h * k);
        void near(Rect actual, Rect expected) {
          for (final (a, e) in [
            (actual.left, expected.left),
            (actual.top, expected.top),
            (actual.width, expected.width),
            (actual.height, expected.height),
          ]) {
            expect(a, closeTo(e, 1), reason: '$actual vs $expected');
          }
        }

        // 모서리: 프레임 150~874, 조각 한 변 204, 굵기 48
        const arm = 204.0;
        final corners = {
          'topLeft': icon(150, 150, arm, arm),
          'topRight': icon(874 - arm, 150, arm, arm),
          'bottomLeft': icon(150, 874 - arm, arm, arm),
          'bottomRight': icon(874 - arm, 874 - arm, arm, arm),
        };
        for (final MapEntry(:key, :value) in corners.entries) {
          final f = find.byKey(ValueKey('intro-corner-$key'));
          near(tester.getRect(f), value);
          final p =
              tester.widget<CustomPaint>(f).painter! as IntroCornerPainter;
          expect(p.stroke, closeTo(48 * k, 1));
          expect(p.radius, closeTo(100 * k, 1));
        }
        // 프레임 가운데 = 화면 가운데
        final tl = tester.getRect(
          find.byKey(const ValueKey('intro-corner-topLeft')),
        );
        final br = tester.getRect(
          find.byKey(const ValueKey('intro-corner-bottomRight')),
        );
        expect(
          (tl.topLeft + br.bottomRight) / 2 - size.center(Offset.zero),
          within(distance: 1, from: Offset.zero),
        );

        near(
          tester.getRect(find.byKey(const ValueKey('intro-re'))),
          icon(318, 407, 277, 169),
        );
        near(
          tester.getRect(find.byKey(const ValueKey('intro-mine'))),
          icon(368, 656, 292, 90),
        );
        near(
          tester.getRect(find.byKey(const ValueKey('intro-dot-top'))),
          icon(684 - 43.5, 379.5 - 43.5, 87, 87),
        );
        near(
          tester.getRect(find.byKey(const ValueKey('intro-dot-bottom'))),
          icon(684 - 43.5, 527 - 43.5, 87, 87),
        );

        await tester.pump(AppMotion.introTotal);
      });
    }
  }

  testWidgets('처음 모서리는 화면 네 귀퉁이(안전 영역 + 18dp)', (tester) async {
    await _pump(tester);
    final f = (360 * 0.4) / 724 * 204;
    expect(
      tester.getRect(find.byKey(const ValueKey('intro-corner-topLeft'))),
      const Rect.fromLTWH(18, 18, 0, 0).topLeft & Size(f, f),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('intro-corner-bottomRight'))),
      Offset(360 - 18 - f, 800 - 18 - f) & Size(f, f),
    );
    await tester.pump(AppMotion.introTotal);
  });
}
