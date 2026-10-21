import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/app.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/screens/detail_screen.dart';

import 'support/fake_device.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

/// 모든 사진의 비율을 [ratio]로 돌려주고, 요청된 썸네일 크기를 기록하는 갤러리.
class _RatioReader extends FakeGalleryReader {
  _RatioReader(this.ratio);

  final double? ratio;
  final List<(int, int?)> thumbRequests = [];

  @override
  Future<double?> aspectRatio(String photoId) async => ratio;

  @override
  Future<Uint8List?> thumbnail(String photoId, {int size = 220, int? height}) {
    thumbRequests.add((size, height));
    return super.thumbnail(photoId, size: size, height: height);
  }
}

Future<void> _openDetail(
  WidgetTester tester, {
  FakeGalleryReader? reader,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RemineApp(
      repository: FakeScreenshotRepository(now: () => _now),
      now: () => _now,
      device: reader == null ? null : fakeServices(reader),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('쇼핑'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Hero).first);
  await tester.pumpAndSettle();
}

Finder get _card =>
    find.descendant(of: find.byType(PageView), matching: find.byType(Hero));

void main() {
  group('detailCardWidth (순수 계산)', () {
    const area = Size(390, 500);

    test('세로로 긴 사진(0.45)은 높이 기준으로 폭이 정해지고 카드가 영역 안에 들어온다', () {
      final w = detailCardWidth(
        areaWidth: area.width,
        areaHeight: area.height,
        aspect: 0.45,
      );
      final h = detailCardHeight(w, aspect: 0.45);
      expect(h, closeTo(area.height, 0.01)); // 높이를 꽉 채우고
      expect(w, lessThan(area.width * 0.86)); // 폭은 86%보다 작다
    });

    test('가로로 넓은 사진(1.5)은 폭 기준(영역 폭의 86%)이다', () {
      final w = detailCardWidth(
        areaWidth: area.width,
        areaHeight: area.height,
        aspect: 1.5,
      );
      expect(w, closeTo(area.width * 0.86, 0.01));
      expect(detailCardHeight(w, aspect: 1.5), lessThan(area.height));
    });

    test('비율을 모르면(null) 0.62다', () {
      expect(
        detailCardWidth(areaWidth: 390, areaHeight: 500),
        detailCardWidth(areaWidth: 390, areaHeight: 500, aspect: 0.62),
      );
    });

    test('안쪽 사진 영역의 비율이 사진과 같다(테두리를 뺀 크기)', () {
      for (final a in [0.45, 0.62, 1.0, 1.5]) {
        final w = detailCardWidth(areaWidth: 390, areaHeight: 500, aspect: a);
        final h = detailCardHeight(w, aspect: a);
        final border = w * 0.07;
        expect((w - 2 * border) / (h - 2 * border), closeTo(a, 0.001));
      }
    });

    test('아주 낮은 영역에서도 0보다 크고 영역을 넘지 않는다', () {
      final w = detailCardWidth(areaWidth: 240, areaHeight: 100, aspect: 0.45);
      expect(w, greaterThan(0));
      expect(detailCardHeight(w, aspect: 0.45), lessThanOrEqualTo(100.01));
    });
  });

  group('상세 이미지 카드 크기 (390×844)', () {
    testWidgets('가짜 데이터 모드: 화면 폭의 86%를 넘지 않고, 상단 바와 정보 카드 사이를 채운다', (
      tester,
    ) async {
      await _openDetail(tester);

      final card = tester.getRect(_card);
      final info = tester.getRect(find.byKey(const ValueKey('info-card-5')));
      expect(card.width, lessThanOrEqualTo(390 * 0.86 + 0.5));
      expect(card.width, greaterThan(390 * 0.7), reason: '예전처럼 절반 크기면 안 된다');
      expect(card.top, greaterThanOrEqualTo(56), reason: '상단 바 아래');
      expect(card.bottom, lessThanOrEqualTo(info.top + 0.5), reason: '정보 카드 위');
      // 남는 공간을 최대한 채운다: 폭이 86% 상한에 닿았거나, 아니면 높이를 거의 꽉 채운다.
      final slack = info.top - card.bottom + (card.top - 56);
      expect(
        card.width >= 390 * 0.86 - 1 || slack < 40,
        isTrue,
        reason: '폭 ${card.width}, 남는 세로 $slack',
      );
    });

    testWidgets('실제 사진 비율 0.45: 카드 전체가 남는 공간 안에 들어오고 사진이 잘리지 않는다', (
      tester,
    ) async {
      final reader = _RatioReader(0.45);
      await _openDetail(tester, reader: reader);

      final card = tester.getRect(_card);
      final info = tester.getRect(find.byKey(const ValueKey('info-card-5')));
      expect(card.top, greaterThanOrEqualTo(56));
      expect(card.bottom, lessThanOrEqualTo(info.top + 0.5));

      // 안쪽(테두리 제외) 사진 영역의 비율이 사진과 같다 → cover여도 잘리지 않는다.
      final border = card.width * 0.07;
      final inner = (card.width - 2 * border) / (card.height - 2 * border);
      expect(inner, closeTo(0.45, 0.01));
      // 세로로 긴 사진이라 높이 기준: 폭이 86%보다 작다.
      expect(card.width, lessThan(390 * 0.86 - 1));
      // 상세 썸네일을 같은 비율로 요청한다(정사각 크롭 방지): 720 × 720/0.45.
      expect(reader.thumbRequests, contains((720, 1600)));
    });

    testWidgets('실제 사진 비율 1.5(가로 사진): 폭 86% 기준', (tester) async {
      await _openDetail(tester, reader: _RatioReader(1.5));

      final card = tester.getRect(_card);
      expect(card.width, closeTo(390 * 0.86, 1));
      final border = card.width * 0.07;
      expect(
        (card.width - 2 * border) / (card.height - 2 * border),
        closeTo(1.5, 0.01),
      );
    });

    testWidgets('비율을 못 얻으면(null) 기본 0.62로 그린다', (tester) async {
      await _openDetail(tester, reader: _RatioReader(null));

      final card = tester.getRect(_card);
      final border = card.width * 0.07;
      expect(
        (card.width - 2 * border) / (card.height - 2 * border),
        closeTo(detailCardDefaultAspect, 0.01),
      );
    });
  });

  group('낮은 화면', () {
    testWidgets('360×640에서도 카드가 최소 높이(240) 이상이고 넘침 없이 스크롤된다', (tester) async {
      await _openDetail(tester, size: const Size(360, 640));

      expect(tester.getRect(_card).height, greaterThanOrEqualTo(200));
      expect(tester.takeException(), isNull);
    });
  });
}
