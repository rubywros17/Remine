import 'dart:convert';

import 'gallery_reader.dart';
import 'privacy/app_rules.dart';
import 'settings_store.dart';

/// Remine 화면을 찍은 캡처를 고르는 규칙. 갤럭시는 우리 앱 화면 캡처 파일명에 앱 이름을 붙이지 않아서
/// (`Screenshot_20261026_151044.jpg`) 파일명만으로는 알 수 없다 → **촬영 시각이 앱이 앞에 있던 구간 안**이면 자기 캡처.
///
/// - 파일명 앱 이름이 `Remine`이면 바로 자기 캡처([isOwnAppCapture]).
/// - 앱 이름이 없는 스크린샷만 시각을 본다. 다른 앱 이름이 붙은 캡처는 시각과 상관없이 자기 캡처가 아니다.
/// - 구간 앞뒤 [margin] 여유: 파일명 시각은 초 단위이고, 앱이 뒤로 가는 순간과 저장 시각이 조금 어긋난다.
/// - [backfill]: 이 규칙이 생기기 전(설치 ~ 이번 업데이트)의 이름 없는 캡처. 구간 기록이 없던 때라
///   한 번 정한 이 기간은 계속 제외한다(빼면 다음 동기화에 다시 보내진다). 그 뒤의 캡처는 구간 규칙만 따른다.
///
/// [Dart 메모] `(DateTime, DateTime)`은 레코드(이름 없는 작은 튜플)다. `r.$1`·`r.$2`로 꺼낸다.
class OwnCaptureRule {
  const OwnCaptureRule({this.intervals = const [], this.backfill});

  static const margin = Duration(seconds: 5);

  final List<(DateTime, DateTime)> intervals;
  final (DateTime, DateTime)? backfill;

  bool isOwn(GalleryPhoto p) => reasonOf(p) != null;

  /// 자기 캡처인 이유(디버그 로그의 사유별 개수). 자기 캡처가 아니면 null.
  OwnReason? reasonOf(GalleryPhoto p) {
    if (isOwnAppCapture(p.fileName)) return OwnReason.name;
    // 이름 있는 캡처(인스타 등)는 구간·정리 기간 안이어도 자기 캡처가 아니다
    if (!isNamelessScreenshot(p.fileName)) return null;
    final t = p.takenAt;
    bool inside((DateTime, DateTime) r, Duration pad) =>
        !t.isBefore(r.$1.subtract(pad)) && !t.isAfter(r.$2.add(pad));
    if (intervals.any((r) => inside(r, margin))) return OwnReason.interval;
    final b = backfill;
    if (b != null && inside(b, Duration.zero)) return OwnReason.backfill;
    return null;
  }
}

/// 자기 캡처로 본 이유: 파일명 앱 이름 Remine / 앱이 앞에 있던 구간 / 1회 정리 기간.
enum OwnReason { name, interval, backfill }

/// 앱이 앞에 있던 구간(resumed ~ paused)을 기기에 기록한다. 최근 [keep]만 두고, 서버로 보내지 않는다.
///
/// 저장은 [SettingsStore.ownCaptureLog] 한 칸(JSON): `{"intervals":[[시작ms,끝ms],…], "open":시작ms, "backfill":[ms,ms]}`.
/// 앱이 앞에 있는 동안 죽으면 끝이 기록되지 않는다 → 다음 실행에서 시작 + [staleCap]까지로 닫는다.
// ponytail: 구간을 JSON 한 칸에 통째로 다시 쓴다(90일 × 하루 수십 번 ≈ 수십 KB). 커지면 전용 표로.
class ForegroundLog {
  ForegroundLog(this._settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const keep = Duration(days: 90);
  static const staleCap = Duration(minutes: 30);

  final SettingsStore _settings;
  final DateTime Function() _now;
  bool _openedThisRun = false;
  Future<void> _last = Future.value();

  /// 읽고-고쳐-쓰기가 겹치지 않게 차례로 돈다(앞→뒤 전환이 연달아 와도 기록이 섞이지 않게).
  Future<void> _serial(Future<void> Function() step) => _last = _last
      .then((_) => step())
      .catchError((Object _) {}); // 기록 실패는 무시(다음 전환에서 다시)

  /// 앱이 앞으로 왔다.
  Future<void> resumed() => _serial(_resumed);

  /// 앱이 뒤로 갔다(paused·hidden·detached).
  Future<void> paused() => _serial(_paused);

  Future<void> _resumed() async {
    final s = await _load();
    final open = s.open;
    if (open != null && _openedThisRun) return; // 이미 열려 있음(inactive → resumed)
    if (open != null) {
      // 지난 실행이 닫지 못한 구간
      final end = open.add(staleCap);
      s.intervals.add((open, end.isBefore(_now()) ? end : _now()));
    }
    s.open = _now();
    _openedThisRun = true;
    await _save(s);
  }

  Future<void> _paused() async {
    final s = await _load();
    final open = s.open;
    if (open == null) return;
    s.intervals.add((open, _now()));
    s.open = null;
    _openedThisRun = false;
    await _save(s);
  }

  /// 처음 한 번만: 구간 기록이 없던 [installedAt] ~ 지금을 이름 없는 캡처 제외 기간으로 정한다.
  /// 이미 정했으면 그대로 둔다(다음 실행에서 기간이 늘어나지 않는다).
  Future<void> ensureBackfill(DateTime installedAt) => _serial(() async {
    final s = await _load();
    if (s.backfill != null) return;
    s.backfill = (installedAt, _now());
    await _save(s);
  });

  /// 지금 시점의 규칙. 열린 구간(앱이 지금 앞에 있음)은 지금까지로 본다.
  Future<OwnCaptureRule> rule() async {
    await _last;
    final s = await _load();
    final open = s.open;
    return OwnCaptureRule(
      intervals: [...s.intervals, if (open != null) (open, _now())],
      backfill: s.backfill,
    );
  }

  Future<_LogState> _load() async {
    final raw = await _settings.ownCaptureLog();
    if (raw == null) return _LogState([], null, null);
    final m = jsonDecode(raw) as Map<String, dynamic>;
    DateTime at(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int);
    (DateTime, DateTime) pair(Object? v) {
      final l = v as List;
      return (at(l[0]), at(l[1]));
    }

    return _LogState(
      [for (final v in m['intervals'] as List) pair(v)],
      m['open'] == null ? null : at(m['open']),
      m['backfill'] == null ? null : pair(m['backfill']),
    );
  }

  Future<void> _save(_LogState s) {
    final since = _now().subtract(keep);
    List<int> ms((DateTime, DateTime) r) => [
      r.$1.millisecondsSinceEpoch,
      r.$2.millisecondsSinceEpoch,
    ];
    return _settings.setOwnCaptureLog(
      jsonEncode({
        'intervals': [
          for (final r in s.intervals)
            if (!r.$2.isBefore(since)) ms(r),
        ],
        'open': s.open?.millisecondsSinceEpoch,
        'backfill': s.backfill == null ? null : ms(s.backfill!),
      }),
    );
  }
}

class _LogState {
  _LogState(this.intervals, this.open, this.backfill);

  final List<(DateTime, DateTime)> intervals;
  DateTime? open;
  (DateTime, DateTime)? backfill;
}
