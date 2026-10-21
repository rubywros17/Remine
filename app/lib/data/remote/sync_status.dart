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

/// 방금 분류된 캡처 한 장(첫 분석 화면 가운데 카드에 실제 썸네일 + 카테고리로 보여 준다).
class RecentShot {
  const RecentShot(this.assetId, this.category);

  final String assetId;
  final Category category;
}

/// 동기화 진행과 안내 상태. 화면(첫 분석 화면, 홈 배너)이 구독한다.
///
/// [Flutter 메모] ChangeNotifier는 값이 바뀌면 구독한 위젯에 알리는 내장 옵저버다([RemineStore]와 같은 방식).
class SyncStatus extends ChangeNotifier {
  SyncStatus({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  bool _running = false;
  bool _finished = false;
  final List<RecentShot> _recent = [];
  int _done = 0;
  int _total = 0;
  DateTime? _startedAt;
  SyncIssue _issue = SyncIssue.none;
  int _failedCount = 0;
  int _intervalMs = 0;
  int _waiting = 0;
  final Map<Category, int> _counts = {};

  bool get running => _running;

  /// 이번 실행이 (성공이든 실패든) 끝났는지. 첫 분석 화면이 완료 상태를 보여 주는 데 쓴다.
  bool get finished => _finished;

  /// 방금 분류된 캡처(최신이 앞, 최대 [maxRecent]장).
  List<RecentShot> get recent => List.unmodifiable(_recent);

  static const maxRecent = 4;
  int get done => _done;
  int get total => _total;
  SyncIssue get issue => _issue;

  /// 분류하지 못해 다음에 다시 보낼 장수([SyncIssue.partial]일 때 안내에 쓴다).
  int get failedCount => _failedCount;

  /// 이번 실행에서 지금까지 분류된 카테고리별 장수.
  Map<Category, int> get counts => Map.unmodifiable(_counts);

  /// 지금 서버 응답을 기다리고 있는 장수(0이면 기다리는 중이 아니다). 화면이 "분류하는 중"을 보여 주는 데 쓴다.
  int get waiting => _waiting;

  /// 서버가 알려 준 장당 분류 간격(ms). 0이면 모른다/대기 없음.
  int get intervalMs => _intervalMs;

  /// 남은 예상 시간. 처음에는 서버가 알려 준 호출 간격으로 어림하고(없으면 null),
  /// 몇 장 처리해 실제 속도를 알게 되면 그 속도로 계산한다.
  Duration? get eta {
    final start = _startedAt;
    if (!_running || start == null) return null;
    final remaining = _total - _done;
    if (_done < minSamplesForEta) {
      return _intervalMs > 0
          ? Duration(milliseconds: _intervalMs * remaining)
          : null;
    }
    final perItem = _now().difference(start).inMilliseconds / _done;
    return Duration(milliseconds: (perItem * remaining).round());
  }

  /// 이만큼은 처리해 봐야 속도를 믿고 예상 시간을 보여 준다.
  static const minSamplesForEta = 5;

  void begin(int total, {int intervalMs = 0}) {
    _running = true;
    _finished = false;
    _recent.clear();
    _intervalMs = intervalMs;
    _waiting = 0;
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

  /// 서버에 [count]장을 보내고 응답을 기다리는 동안 켠다(응답이 오면 0으로).
  void setWaiting(int count) {
    if (_waiting == count) return;
    _waiting = count;
    notifyListeners();
  }

  /// [category]로 분류된 한 장을 센다. [assetId]를 주면 "방금 분류된 캡처"에도 올린다(숨김 캡처에는 주지 않는다).
  void count(Category category, {String? assetId}) {
    _counts[category] = (_counts[category] ?? 0) + 1;
    if (assetId != null) {
      _recent.insert(0, RecentShot(assetId, category));
      if (_recent.length > maxRecent) _recent.removeLast();
    }
  }

  void finish({SyncIssue issue = SyncIssue.none, int failedCount = 0}) {
    _running = false;
    _finished = true;
    _waiting = 0;
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

  /// 서버 응답을 기다리는 동안 보여 줄 문장. 숫자가 한참 안 바뀌어도 멈춘 게 아니라는 걸 알려 준다.
  String? get waitingMessage {
    if (_waiting == 0) return null;
    final batch = _intervalMs > 0
        ? ' 한 묶음에 ${formatBatchTime(Duration(milliseconds: _intervalMs * _waiting))} 정도 걸려요.'
        : '';
    return '$_waiting장을 분류하는 중이에요.$batch';
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

/// 한 묶음이 걸리는 시간 문구: "약 1분 30초", "약 40초".
String formatBatchTime(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 60) return '약 $seconds초';
  final m = seconds ~/ 60;
  final r = seconds % 60;
  return r == 0 ? '약 $m분' : '약 $m분 $r초';
}
