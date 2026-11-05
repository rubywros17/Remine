import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/remote/remote_services.dart';
import 'analysis_screen.dart';

/// 서버 연동 모드에서 동기화를 시작하고, **첫 분석**(처음 설치해 아직 한 번도 끝내지 못한 동안)에는 진행 화면을 보여 준다.
///
/// - 분석 화면의 "홈에서 먼저 볼래요"를 누르면 바로 [child](홈)로 나간다. 동기화는 앱이 열려 있는 동안 계속 돌고,
///   배치가 끝날 때마다 홈이 새로 불러온다.
/// - 첫 분석이 끝나도(또는 서버에 닿지 못해 멈춰도) 자동으로 넘어가지 않는다. 완료 상태에서 [홈으로]를 눌러야 [child]가 열린다.
/// - 이후 실행은 곧바로 [child]를 보여 주고 뒤에서 새로 생기거나 바뀐 캡처만 증분으로 보낸다.
/// - 앱이 다시 앞으로 돌아올 때(resumed)도 한 번 더 시작한다. 이미 돌고 있으면 겹쳐 돌지 않는다.
/// - 푸시: 시작할 때 서버 토큰을 알림 설정에 맞춘다. 알림을 묻는 것은 이 앞의 NotificationGate다.
/// - 첫 분석 화면이 떠 있고 아직 끝나지 않은 동안 화면 꺼짐을 막는다(화면이 꺼지면 앱이 멈춰 동기화가 끊긴다).
///   끝나거나 홈으로 나가거나 이 위젯이 사라지면 푼다.
class SyncGate extends StatefulWidget {
  const SyncGate({
    super.key,
    required this.remote,
    required this.child,
    this.keepScreenOn = keepScreenOnByChannel,
  });

  final RemoteServices remote;
  final Widget child;

  /// 화면 꺼짐 방지 켜기/끄기. 테스트는 기록용 함수를 넘긴다.
  final ValueChanged<bool> keepScreenOn;

  @override
  State<SyncGate> createState() => _SyncGateState();
}

class _SyncGateState extends State<SyncGate> with WidgetsBindingObserver {
  bool _loaded = false;
  bool _showAnalysis = false;
  bool _screenOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.remote.status.addListener(_updateScreenOn);
    _start();
  }

  void _updateScreenOn() {
    final want = _showAnalysis && !widget.remote.status.finished;
    if (want == _screenOn) return;
    _screenOn = want;
    widget.keepScreenOn(want);
  }

  Future<void> _start() async {
    final first = !await widget.remote.state.firstSyncDone();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      // 자동 동기화가 꺼져 있으면(디버그) 진행 화면이 기다리기만 하므로 바로 홈
      _showAnalysis = first && widget.remote.sync.autoSync;
    });
    _updateScreenOn();
    widget.remote.sync.startTokenSync(); // 기다리지 않는다(실패해도 동기화와 무관)
    // 끝나도 자동으로 홈으로 넘어가지 않는다: 분석 화면이 완료 상태("N장 정리했어요")와 [홈에서 둘러보기] 버튼을 보여 준다.
    await widget.remote.sync.runAuto();
  }

  /// 분석 화면의 홈 버튼("홈에서 먼저 볼래요" / 완료 후 [홈으로]).
  void _home() {
    setState(() => _showAnalysis = false);
    _updateScreenOn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded) {
      widget.remote.sync.runAuto(); // 진행 중이면 새로 시작하지 않는다
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.remote.status.removeListener(_updateScreenOn);
    if (_screenOn) widget.keepScreenOn(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (!_showAnalysis) return widget.child;
    return AnalysisScreen(status: widget.remote.status, onHome: _home);
  }
}

/// 안드로이드 창 플래그(FLAG_KEEP_SCREEN_ON)로 화면 꺼짐을 막는다(MainActivity.kt, 권한 불필요).
/// 크롬·테스트처럼 채널이 없으면 아무것도 하지 않는다.
void keepScreenOnByChannel(bool on) {
  const MethodChannel('remine/settings')
      .invokeMethod<void>('keepScreenOn', on)
      .catchError(
        (Object _) {},
        test: (e) => e is PlatformException || e is MissingPluginException,
      );
}
