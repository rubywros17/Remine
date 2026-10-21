import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../models/category.dart';
import 'api_client.dart';

/// 동기화가 끝났을 때(또는 목록을 받다가) 사용자에게 안내해야 하는 상태.
enum SyncIssue {
  none,

  /// 서버에 닿지 못했다(네트워크 없음, 서버 꺼짐, 시간 초과).
  offline,

  /// 서버가 오류를 돌려줬다.
  server,

  /// 일부 캡처만 분류하지 못했다(다음 실행 때 다시 보낸다).
  partial,
}

/// 동기화 진행과 안내 상태. 화면(첫 분석 화면, 홈 배너)이 구독한다.
///
/// [Flutter 메모] ChangeNotifier는 값이 바뀌면 구독한 위젯에 알리는 내장 옵저버다([RemineStore]와 같은 방식).
class SyncStatus extends ChangeNotifier {
  SyncStatus({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  bool _running = false;
  int _done = 0;
  int _total = 0;
  DateTime? _startedAt;
  SyncIssue _issue = SyncIssue.none;
  int _failedCount = 0;
  final Map<Category, int> _counts = {};

  bool get running => _running;
  int get done => _done;
  int get total => _total;
  SyncIssue get issue => _issue;

  /// 분류하지 못해 다음에 다시 보낼 장수([SyncIssue.partial]일 때 안내에 쓴다).
  int get failedCount => _failedCount;

  /// 이번 실행에서 지금까지 분류된 카테고리별 장수.
  Map<Category, int> get counts => Map.unmodifiable(_counts);

  /// 남은 예상 시간. 몇 장이라도 처리해 속도를 알 수 있기 전에는 null.
  Duration? get eta {
    final start = _startedAt;
    if (!_running || start == null || _done < minSamplesForEta) return null;
    final perItem = _now().difference(start).inMilliseconds / _done;
    return Duration(milliseconds: (perItem * (_total - _done)).round());
  }

  /// 이만큼은 처리해 봐야 속도를 믿고 예상 시간을 보여 준다.
  static const minSamplesForEta = 5;

  void begin(int total) {
    _running = true;
    _done = 0;
    _total = total;
    _startedAt = _now();
    _counts.clear();
    _failedCount = 0;
    if (_issue != SyncIssue.partial) _issue = SyncIssue.none;
    notifyListeners();
  }

  void advance(int by) {
    _done = (_done + by).clamp(0, _total);
    notifyListeners();
  }

  void count(Category category) {
    _counts[category] = (_counts[category] ?? 0) + 1;
  }

  void finish({SyncIssue issue = SyncIssue.none, int failedCount = 0}) {
    _running = false;
    _issue = issue;
    _failedCount = failedCount;
    notifyListeners();
  }

  /// 목록·요약을 받으려던 결과. 실패하면 안내를 켜고, 성공하면 연결 문제 안내를 끈다.
  void reportFetch(ApiFailure? failure) {
    final next = switch (failure) {
      null =>
        (_issue == SyncIssue.offline || _issue == SyncIssue.server)
            ? SyncIssue.none
            : _issue,
      ApiFailure.offline => SyncIssue.offline,
      _ => SyncIssue.server,
    };
    if (next != _issue) {
      _issue = next;
      notifyListeners();
    }
  }

  /// [SyncIssue]를 사용자에게 보여 줄 문장. 개인정보나 원인 상세는 담지 않는다.
  String? get issueMessage => switch (_issue) {
    SyncIssue.none => null,
    SyncIssue.offline => '서버에 연결하지 못했어요. 이미 정리된 캡처는 그대로 볼 수 있어요.',
    SyncIssue.server => '서버가 잠시 불안정해요. 조금 뒤에 다시 시도할게요.',
    SyncIssue.partial => '$_failedCount장은 다음에 다시 분류할게요.',
  };
}

/// "약 3분 남았어요" 같은 남은 시간 문구. 1분 미만은 "1분 미만".
String formatEta(Duration eta) {
  if (eta.inSeconds < 60) return '1분 미만 남았어요';
  final minutes = (eta.inSeconds / 60).ceil();
  if (minutes < 60) return '약 $minutes분 남았어요';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '약 $hours시간 남았어요' : '약 $hours시간 $rest분 남았어요';
}
