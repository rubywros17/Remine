import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/models/category.dart';

final _now = DateTime(2026, 10, 19, 12, 0); // 월요일

FakeScreenshotRepository _repo() => FakeScreenshotRepository(now: () => _now);

void main() {
  group('샘플 데이터', () {
    test('30개이고 카테고리가 고르게 들어 있다', () async {
      final summary = await _repo().summary();

      expect(summary.total, 30);
      expect(
        summary.categories.map((c) => c.category),
        Category.values,
      ); // 7개 전부, 서버 순서
      expect(summary.of(Category.shopping).count, 6);
      for (final c in Category.values.where((c) => c != Category.shopping)) {
        expect(summary.of(c).count, 4);
      }
    });
  });

  group('목록', () {
    test('최신순이고 카테고리·태그로 거른다', () async {
      final all = await _repo().list(size: 100);
      final times = all.items.map((s) => s.takenAt).toList();
      expect([...times]..sort((a, b) => b.compareTo(a)), times);

      final shopping = await _repo().list(category: Category.shopping);
      expect(shopping.totalElements, 6);
      expect(
        shopping.items.every((s) => s.category == Category.shopping),
        isTrue,
      );

      final tagged = await _repo().list(
        category: Category.shopping,
        tag: '니트가디건',
      );
      expect(tagged.totalElements, 4);
    });

    test('페이지를 나눈다', () async {
      final page = await _repo().list(page: 1, size: 12);
      expect(page.items.length, 12);
      expect(page.totalPages, 3);
      expect(page.totalElements, 30);
    });
  });

  group('요약', () {
    test('대표 태그는 빈도 내림차순·이름순 3개, 최신 localAssetId는 최대 4개', () async {
      final shopping = (await _repo().summary()).of(Category.shopping);

      expect(shopping.topTags.first, '니트가디건');
      expect(shopping.topTags.length, 3);
      expect(shopping.recentAssetIds.length, 4);
    });

    test('홈 정렬은 개수 내림차순에 기타가 마지막이고, 가장 많은 카테고리를 알려준다', () async {
      final summary = await _repo().summary();
      final sorted = summary.sortedForHome.map((c) => c.category).toList();

      expect(sorted.first, Category.shopping);
      expect(sorted.last, Category.etc);
      expect(summary.largest, Category.shopping);
    });
  });

  group('카테고리 수정', () {
    test('다른 값으로 옮기면 USER가 되고 autoCategory·태그는 그대로이며 집계에 바로 반영된다', () async {
      final repo = _repo();
      final target = (await repo.list(category: Category.shopping)).items.first;

      final result = await repo.updateCategory(target.id, Category.place);

      expect(result.category, Category.place);
      expect(result.autoCategory, Category.shopping);
      expect(result.categorySource, CategorySource.user);
      final summary = await repo.summary();
      expect(summary.of(Category.shopping).count, 5);
      expect(summary.of(Category.place).count, 5);
      final moved = (await repo.list(category: Category.place)).items
          .firstWhere((s) => s.id == target.id);
      expect(moved.tags, target.tags);
    });

    test('같은 값으로 수정해도 USER가 된다(사용자 확인)', () async {
      final repo = _repo();
      final target = (await repo.list(category: Category.info)).items.first;

      final result = await repo.updateCategory(target.id, Category.info);

      expect(result.category, Category.info);
      expect(result.categorySource, CategorySource.user);
    });

    test('없는 id는 실패한다', () async {
      expect(_repo().updateCategory(9999, Category.etc), throwsStateError);
    });
  });

  group('잊은 관심사', () {
    test('니트가디건 ×4, 9일째 잠자는 중이다', () async {
      final interests = await _repo().interests();

      expect(interests.first.tag, '니트가디건');
      expect(interests.first.captureCount, 4);
      expect(interests.first.dormantDays, 9);
      expect(interests.first.spanDays, 14);
      expect(interests.first.category, Category.shopping);
      expect(interests.first.screenshotIds.length, 4);
    });
  });
}
