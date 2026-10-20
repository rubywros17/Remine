import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/category_summary.dart';
import 'package:remine/models/category_update.dart';
import 'package:remine/models/screenshot_item.dart';

/// 서버가 실제로 내려주는 JSON 모양(docs/spec.md 9장, 서버 DTO)으로 파싱되는지 확인한다.
void main() {
  test('GET /api/screenshots 페이지 응답', () {
    const json = '''
    {"items":[{"id":7,"localAssetId":"a1","takenAt":"2026-10-19T10:00:00","sourceApp":"COUPANG",
               "category":"SHOPPING","summary":"요약","tags":["구매","원"]},
              {"id":8,"localAssetId":"a2","takenAt":"2026-10-18T09:30:00","sourceApp":null,
               "category":"ETC","summary":null,"tags":[]}],
     "page":0,"size":30,"totalElements":2,"totalPages":1}''';

    final page = ScreenshotPage.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

    expect(page.totalElements, 2);
    expect(page.items.first.id, 7);
    expect(page.items.first.takenAt, DateTime(2026, 10, 19, 10));
    expect(page.items.first.category, Category.shopping);
    expect(page.items.first.tags, ['구매', '원']);
    expect(page.items.first.autoCategory, isNull); // 목록 응답에는 아직 없다
    expect(page.items.last.sourceApp, isNull);
    expect(page.items.last.summary, isNull);
  });

  test('GET /api/categories/summary 응답', () {
    const json = '''
    {"categories":[{"category":"SHOPPING","count":42,"topTags":["니트"],"recentAssetIds":["a1","a2"]},
                   {"category":"ETC","count":0,"topTags":[],"recentAssetIds":[]}]}''';

    final summary = CategorySummary.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

    expect(summary.categories.length, 2);
    expect(summary.total, 42);
    expect(summary.of(Category.shopping).recentAssetIds, ['a1', 'a2']);
  });

  test('PATCH /api/screenshots/{id}/category 응답', () {
    const json =
        '{"id":5,"category":"PLACE","autoCategory":"SHOPPING","categorySource":"USER"}';

    final update = CategoryUpdate.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

    expect(update.category, Category.place);
    expect(update.autoCategory, Category.shopping);
    expect(update.categorySource, CategorySource.user);
  });

  test('알 수 없는 카테고리 값은 거부한다', () {
    expect(() => Category.fromJson('MOVIE_DRAMA'), throwsFormatException);
  });
}
