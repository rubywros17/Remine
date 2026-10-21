import 'package:flutter/material.dart';

import '../data/remote/remote_services.dart';
import 'analysis_screen.dart';

/// 서버 연동 모드에서 동기화를 시작하고, **첫 분석**(처음 설치해 아직 한 번도 끝내지 못한 동안)에는 진행 화면을 보여 준다.
///
/// - 분석 화면의 "홈에서 먼저 볼래요"를 누르면 바로 [child](홈)로 나간다. 동기화는 앱이 열려 있는 동안 계속 돌고,
///   배치(20장)가 끝날 때마다 홈이 새로 불러온다.
/// - 첫 분석이 끝났거나 서버에 닿지 못해 멈추면 자동으로 [child]로 넘어간다(안내는 홈 배너가 맡는다).
/// - 이후 실행은 곧바로 [child]를 보여 주고 뒤에서 새로 생기거나 바뀐 캡처만 증분으로 보낸다.
/// - 앱이 다시 앞으로 돌아올 때(resumed)도 한 번 더 시작한다. 이미 돌고 있으면 겹쳐 돌지 않는다.
class SyncGate extends StatefulWidget {
  const SyncGate({super.key, required this.remote, required this.child});

  final RemoteServices remote;
  final Widget child;

  @override
  State<SyncGate> createState() => _SyncGateState();
}

class _SyncGateState extends State<SyncGate> with WidgetsBindingObserver {
  bool _loaded = false;
  bool _showAnalysis = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final first = !await widget.remote.state.firstSyncDone();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _showAnalysis = first;
    });
    await widget.remote.sync.run();
    if (mounted && _showAnalysis) setState(() => _showAnalysis = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded) {
      widget.remote.sync.run(); // 진행 중이면 새로 시작하지 않는다
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_showAnalysis) return widget.child;
    return AnalysisScreen(
      status: widget.remote.status,
      onHome: () => setState(() => _showAnalysis = false),
    );
  }
}
