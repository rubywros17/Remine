import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../widgets/home_widgets.dart';
import 'home_screen.dart';
import 'interests_screen.dart';
import 'tidy_screen.dart';

/// 하단 탭바가 붙은 첫 화면(서랍·관심사·정리).
///
/// 관심사 탭으로 갈 때만 페이드 스루: 이전 탭이 먼저 사라지고(0~225ms) 지도 바탕이 뒤이어 들어온다(180ms~).
/// 다른 탭 전환과 "애니메이션 줄이기"는 즉시 바뀐다.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen>
    with SingleTickerProviderStateMixin {
  static const _interests = 1;

  int _index = 0;

  /// 페이드 스루 중 사라지는 탭. 없으면 null.
  int? _from;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(
      milliseconds: AppBrain.tabInStart + AppBrain.tabIn,
    ),
  )..addStatusListener((s) {
      if (s.isCompleted) setState(() => _from = null);
    });

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    final fade = i == _interests && !AppMotion.reduced(context);
    setState(() {
      _from = fade ? _index : null;
      _index = i;
    });
    if (fade) {
      _fade.forward(from: 0);
    } else {
      _fade.stop();
    }
  }

  double _opacity(int i) {
    if (_from == null) return 1;
    final ms = _fade.value * (AppBrain.tabInStart + AppBrain.tabIn);
    if (i == _from) {
      return 1 -
          AppBrain.faceOutCurve.transform(
            (ms / AppBrain.tabOut).clamp(0.0, 1.0),
          );
    }
    return AppBrain.faceInCurve.transform(
      ((ms - AppBrain.tabInStart) / AppBrain.tabIn).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const HomeScreen(),
      InterestsScreen(active: _index == _interests),
      TidyScreen(active: _index == 2),
    ];
    return Scaffold(
      // 탭을 바꿔도 각 탭의 상태(스크롤 위치 등)를 유지한다(숨은 탭은 Visibility가 그대로 살려 둔다).
      // 숨은 탭도 살아 있어서 홈과 관심사 탭의 같은 캡처 썸네일 Hero 태그가 겹친다 → 보이는 탭만 Hero를 켠다.
      // [Flutter 메모] IndexedStack은 한 탭만 그려서, 두 탭이 겹쳐 사라지고 나타나는 동안은 Stack + Visibility로 그린다.
      body: AnimatedBuilder(
        animation: _fade,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (final (i, tab) in tabs.indexed)
              Visibility(
                visible: i == _index || i == _from,
                maintainState: true,
                child: Opacity(
                  opacity: _opacity(i),
                  child: HeroMode(enabled: i == _index, child: tab),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AppTabBar(index: _index, onChanged: _select),
    );
  }
}
