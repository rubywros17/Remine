import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/tokens.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';
import 'package:remine/widgets/interest_brain_map.dart';

// 뇌 지도 칩 배치를 실데이터로 확인한다. 테스트 기본 폰트는 글자 폭이 실제보다 넓어서
// 여백·간격을 재려면 앱 폰트(Pretendard)를 불러와야 한다.

Interest _i(String tag, int count, Category c, {bool forgotten = false}) =>
    Interest(
      tag: tag,
      category: c,
      forgotten: forgotten,
      captureCount: count,
      dormantDays: forgotten ? 40 : 1,
      peakMonth: 10,
      peakMonthCount: count,
      latestMonth: 10,
      latestMonthCount: count,
      recent: const [],
    );

/// 실기기 데이터: 1등 집들이선물(쇼핑), 데스크오가나이저(쇼핑), 베이킹(혼자), 오잉보잉(잊은),
/// 도안·뜨개질·키링(요즘). 도안·뜨개질·오잉보잉·키링은 같은 카테고리.
final _real = [
  _i('집들이선물', 12, Category.shopping, forgotten: true),
  _i('데스크오가나이저', 10, Category.shopping, forgotten: true),
  _i('베이킹', 8, Category.place, forgotten: true),
  _i('오잉보잉', 7, Category.entertainment, forgotten: true),
  _i('도안', 9, Category.entertainment),
  _i('뜨개질', 8, Category.entertainment),
  _i('키링', 6, Category.entertainment),
];

void main() {
  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final f in const [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
    ]) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  });

  test('같은 카테고리 넷(도안·뜨개질·오잉보잉·키링)은 이웃 자리로 이어진다', () {
    final nodes = layoutNodes(_real);
    expect(nodes.first.interest.tag, '집들이선물');
    expect(nodes.first.seat, -1, reason: '1등은 가운데');
    final seats = {
      for (final n in nodes)
        if (n.interest.category == Category.entertainment) n.seat,
    };
    expect(seats, hasLength(4));
    // 원형 6자리 중 4자리가 한 덩어리 = 이웃 쌍이 3개.
    final pairs = [
      for (var k = 0; k < 6; k++)
        if (seats.contains(k) && seats.contains((k + 1) % 6)) k,
    ];
    expect(pairs, hasLength(3), reason: '자리 $seats');
  });

  // 360×800·412×915 화면의 지도 캔버스 크기.
  for (final (name, size, scale) in const [
    ('360×800', Size(320, 470), 1.0),
    ('412×915', Size(372, 560), 1.0),
    ('412×915 글자 1.3배', Size(372, 560), 1.3),
  ]) {
    test('실데이터 7개: 윤곽 여백 8px 이상 · 칩 사이 10px 이상 · 이웃 거리 고르게 · $name', () {
      final chips = layoutChips(
        layoutNodes(_real),
        size,
        TextScaler.linear(scale),
      );
      expect(chips, hasLength(7));
      for (final (i, a) in chips.indexed) {
        expect(
          chipFitsBrain(size, a.rect, AppBrain.chipBrainMinMargin),
          isTrue,
          reason: '${a.node.interest.tag} ${a.rect}',
        );
        expect(a.shrink, greaterThanOrEqualTo(0.85));
        for (final b in chips.skip(i + 1)) {
          expect(
            a.rect.inflate(4.9).overlaps(b.rect.inflate(4.9)),
            isFalse,
            reason: '${a.node.interest.tag} ↔ ${b.node.interest.tag} 10px 미만',
          );
        }
      }
      // 이웃: 가운데-둘레 6쌍 + 둘레끼리 원형 6쌍.
      final center = chips.first.rect.center;
      final bySeat = {
        for (final c in chips.skip(1)) c.node.seat: c.rect.center,
      };
      final d = [
        for (final p in bySeat.values) (p - center).distance,
        for (var k = 0; k < 6; k++)
          (bySeat[k]! - bySeat[(k + 1) % 6]!).distance,
      ];
      expect(d.reduce(max) / d.reduce(min), lessThanOrEqualTo(1.4));
    });
  }
}
