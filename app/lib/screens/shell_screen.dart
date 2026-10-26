import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../widgets/home_widgets.dart';
import 'home_screen.dart';
import 'interests_screen.dart';

/// 하단 탭바가 붙은 첫 화면. 검색 탭은 아직 빈 자리다.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack은 탭을 바꿔도 각 탭의 상태(스크롤 위치 등)를 유지한다.
      // 숨은 탭도 살아 있어서 홈과 관심사 탭의 같은 캡처 썸네일 Hero 태그가 겹친다 → 보이는 탭만 Hero를 켠다.
      body: IndexedStack(
        index: _index,
        children: [
          for (final (i, tab) in [
            const HomeScreen(),
            InterestsScreen(active: _index == 1),
            const _EmptyTab(message: '검색도 곧 열릴 거야'),
          ].indexed)
            HeroMode(enabled: i == _index, child: tab),
        ],
      ),
      bottomNavigationBar: AppTabBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: AppText.body.copyWith(color: AppColors.inkSub)),
  );
}
