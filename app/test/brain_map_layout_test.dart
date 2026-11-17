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
        _expectFontFloor(a);
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

  test('넘치는 칩만 따로 줄인다: 긴 칩은 작게, 짧은 칩은 그대로, 둘레 칩 높이는 같다 · 360×800', () {
    final chips = layoutChips(
      layoutNodes(_real),
      const Size(320, 470),
      TextScaler.noScaling,
    );
    double shrinkOf(String tag) =>
        chips.firstWhere((c) => c.node.interest.tag == tag).shrink;
    expect(shrinkOf('데스크오가나이저'), lessThan(shrinkOf('도안')));
    expect(shrinkOf('키링'), 1, reason: '짧은 칩은 줄이지 않는다');
    _expectSameRingHeight(chips);
    // 가로 패딩도 글자 배율만큼 준다(칩 폭 = 글자 폭 + 줄인 패딩).
    final desk = chips.firstWhere((c) => c.node.interest.tag == '데스크오가나이저');
    expect(
      desk.padding.horizontal,
      closeTo(AppBrain.chipPadding.horizontal * desk.shrink, 0.01),
    );
  });

  // 14자 키워드가 섞인 7개: 말줄임 없이 글자 크기로만 맞춘다.
  final long = [
    _i('겨울캠핑장비추천리스트총정리', 9, Category.shopping),
    _i('니트가디건코디', 8, Category.entertainment),
    _i('제주도한달살기숙소', 7, Category.place, forgotten: true),
    _i('홈카페레시피', 6, Category.info),
    _i('아이폰케이스', 5, Category.chat),
    _i('주말브런치맛집', 4, Category.schedule, forgotten: true),
    _i('전시회일정정리', 3, Category.etc),
  ];
  for (final (name, size, scale, count) in const [
    // 360×800: 글자 최소 11 때문에 둘레 칩은 85%(11/13)까지만 줄어 7개가 다 못 앉는다(5개).
    ('360×800', Size(320, 470), 1.0, 5),
    ('412×915', Size(372, 560), 1.0, 7),
  ]) {
    test(
      '긴 키워드: 글자 최소 11 · 1등 85% 이상 · 칩 사이 10px · 캔버스 안 · 칩 $count개 · $name',
      () {
        final chips = layoutChips(
          layoutNodes(long),
          size,
          TextScaler.linear(scale),
        );
        expect(chips, hasLength(count));
        expect(chips.first.shrink, greaterThanOrEqualTo(0.85 - 1e-9));
        _expectSameRingHeight(chips);
        final canvas = (Offset.zero & size).inflate(0.5);
        for (final (i, a) in chips.indexed) {
          _expectFontFloor(a);
          expect(
            canvas.contains(a.rect.topLeft) &&
                canvas.contains(a.rect.bottomRight),
            isTrue,
          );
          for (final b in chips.skip(i + 1)) {
            expect(a.rect.inflate(4.9).overlaps(b.rect.inflate(4.9)), isFalse);
          }
        }
      },
    );
  }
}

/// 글자는 [AppBrain.chipMinFont] 아래로 안 내려간다.
void _expectFontFloor(BrainChip c) {
  final base = c.top ? AppBrain.chipTopFont : AppBrain.chipFont;
  expect(
    base * c.shrink,
    greaterThanOrEqualTo(AppBrain.chipMinFont - 1e-9),
    reason: '${c.node.interest.tag} ${c.shrink}',
  );
}

/// 둘레 칩은 글자 배율이 달라도 높이가 같다(줄 맞춤).
void _expectSameRingHeight(List<BrainChip> chips) {
  final heights = {
    for (final c in chips.skip(1)) c.rect.height.toStringAsFixed(2),
  };
  expect(heights, hasLength(1), reason: '$heights');
}
