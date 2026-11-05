import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/remote/sync_status.dart';
import '../models/category.dart';
import 'analysis_screen.dart';

/// [디버그 전용] 첫 분석 화면을 가짜 진행으로 보여 준다. 동기화·서버·Gemini를 부르지 않는다.
/// 기본은 0 → 300장 약 20초, [measured]면 묶음 재현(16장씩 72초 간격).
/// 실제 화면을 그대로 쓰고 진행 값만 이 화면의 [SyncStatus]에 직접 넣는다. 진입점이 `kDebugMode`로 막혀 있다.
class AnalysisPreviewScreen extends StatefulWidget {
  const AnalysisPreviewScreen({
    super.key,
    this.assetIds = const [],
    this.measured = false,
  });

  /// "방금 꺼낸 캡처" 카드에 보여 줄 기기 사진 id. 비면(가짜 데이터 모드) 카드는 색 블록이다.
  final List<String> assetIds;

  /// 묶음이 띄엄띄엄 오는 실제 흐름을 재현한다(카드 간격·대기 애니메이션 확인용).
  final bool measured;

  @override
  State<AnalysisPreviewScreen> createState() => _AnalysisPreviewScreenState();
}

class _AnalysisPreviewScreenState extends State<AnalysisPreviewScreen> {
  static const _total = 300;
  static const _tick = Duration(milliseconds: 66); // 300장 × 66ms ≈ 20초
  static const _batchSize = 16;
  static const _batchEvery = Duration(seconds: 72);

  /// 이만큼마다 한 장만 카드로 띄운다(초당 3장 → 큐가 쌓이는 모습까지 보인다). 나머지는 숨김처럼 칸 숫자만 오른다.
  static const _cardEvery = 5;

  // 많이 나올 카테고리를 더 많이 넣어 뽑는다.
  static const _weighted = [
    Category.shopping,
    Category.shopping,
    Category.shopping,
    Category.info,
    Category.info,
    Category.etc,
    Category.etc,
    Category.place,
    Category.chat,
    Category.entertainment,
    Category.schedule,
  ];

  final _status = SyncStatus();
  final _random = Random();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    if (widget.measured) {
      _status.begin(_total, intervalMs: 4500);
      _status.setWaiting(_batchSize);
      _timer = Timer.periodic(_batchEvery, (_) => _batch());
    } else {
      _status.begin(_total);
      _timer = Timer.periodic(_tick, (_) => _step());
    }
  }

  String _assetId(int n) {
    final ids = widget.assetIds;
    return ids.isEmpty ? 'preview-$n' : ids[n % ids.length];
  }

  Category _pick() => _weighted[_random.nextInt(_weighted.length)];

  void _batch() {
    final size = min(_batchSize, _total - _status.done);
    for (var i = 1; i <= size; i++) {
      _status.count(_pick(), assetId: _assetId(_status.done + i));
    }
    _status.advance(size);
    if (_status.done >= _total) {
      _timer.cancel();
      _status.finish();
    }
  }

  void _step() {
    final n = _status.done + 1;
    _status.count(_pick(), assetId: n % _cardEvery != 0 ? null : _assetId(n));
    _status.advance(1); // count는 알리지 않으므로 advance가 화면을 갱신한다
    if (n == _total) {
      _timer.cancel();
      _status.finish();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnalysisScreen(
      status: _status,
      onHome: () => Navigator.of(context).pop(),
    );
  }
}
