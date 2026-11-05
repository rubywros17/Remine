import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/remote/sync_status.dart';
import '../models/category.dart';
import 'analysis_screen.dart';

/// [디버그 전용] 첫 분석 화면을 가짜 진행(0 → 300장, 약 20초)으로 보여 준다. 동기화·서버·Gemini를 부르지 않는다.
/// 실제 화면을 그대로 쓰고 진행 값만 이 화면의 [SyncStatus]에 직접 넣는다. 진입점이 `kDebugMode`로 막혀 있다.
class AnalysisPreviewScreen extends StatefulWidget {
  const AnalysisPreviewScreen({super.key, this.assetIds = const []});

  /// "방금 꺼낸 캡처" 카드에 보여 줄 기기 사진 id. 비면(가짜 데이터 모드) 카드는 색 블록이다.
  final List<String> assetIds;

  @override
  State<AnalysisPreviewScreen> createState() => _AnalysisPreviewScreenState();
}

class _AnalysisPreviewScreenState extends State<AnalysisPreviewScreen> {
  static const _total = 300;
  static const _tick = Duration(milliseconds: 66); // 300장 × 66ms ≈ 20초

  /// 이만큼마다 카드를 바꾼다(약 1초에 한 번). 매 장 바꾸면 썸네일을 읽기 전에 카드가 밀려 깜빡인다.
  static const _cardEvery = 15;

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

  final _status = SyncStatus()..begin(_total);
  final _random = Random();
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => _step());
  }

  void _step() {
    final n = _status.done + 1;
    final ids = widget.assetIds;
    _status.count(
      _weighted[_random.nextInt(_weighted.length)],
      assetId: n % _cardEvery != 0
          ? null
          : ids.isEmpty
          ? 'preview-$n'
          : ids[n % ids.length],
    );
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
