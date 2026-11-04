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

    test('홈 정렬은 개수 내림차순에 기타가 마지막이다', () async {
      final summary = await _repo().summary();
      final sorted = summary.sortedForHome.map((c) => c.category).toList();

      expect(sorted.first, Category.shopping);
      expect(sorted.last, Category.etc);
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

  group('휴지통', () {
    test('휴지통 항목은 목록·요약·관심사에서 빠지고 복원하면 원래 자리로 돌아온다', () async {
      final repo = _repo();
      final before = (await repo.list(
        category: Category.shopping,
        size: 100,
      )).items;
      final target = before[1]; // 두 번째(최신순)

      await repo.trash(target.id);

      final list = (await repo.list(
        category: Category.shopping,
        size: 100,
      )).items;
      expect(list.map((s) => s.id), isNot(contains(target.id)));
      expect(list.length, 5);
      final summary = await repo.summary();
      expect(summary.of(Category.shopping).count, 5);
      expect(summary.total, 29);
      expect(
        summary.of(Category.shopping).recentAssetIds,
        isNot(contains(target.localAssetId)),
      );
      expect(repo.trashedIds, {target.id});

      await repo.restore(target.id);

      final restored = (await repo.list(
        category: Category.shopping,
        size: 100,
      )).items;
      expect(restored.map((s) => s.id), before.map((s) => s.id)); // 같은 순서
      expect((await repo.summary()).total, 30);
      expect(repo.trashedIds, isEmpty);
    });

    test('관심사 횟수에서도 빠진다', () async {
      final repo = _repo();
      final interest = (await repo.interests()).first; // 니트가디건 ×4
      await repo.trash(interest.recent.first.id);

      expect((await repo.interests()).first.captureCount, 3);
    });

    test('관심사 횟수가 기준(3) 아래로 내려가면 관심사에서 빠진다', () async {
      final repo = _repo();
      final interest = (await repo.interests()).first; // 니트가디건 ×4
      await repo.trash(interest.recent[0].id);
      await repo.trash(interest.recent[1].id);

      expect(
        (await repo.interests()).map((i) => i.tag),
        isNot(contains('니트가디건')),
      );
      await repo.restore(interest.recent[1].id);
      expect((await repo.interests()).first.tag, '니트가디건');
    });

    test('휴지통 항목은 카테고리를 수정할 수 없다', () async {
      final repo = _repo();
      final target = (await repo.list(size: 100)).items.first;
      await repo.trash(target.id);

      expect(repo.updateCategory(target.id, Category.etc), throwsStateError);
    });

    test('없는 id는 휴지통에 넣을 수 없다', () async {
      expect(_repo().trash(9999), throwsStateError);
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
      expect(interests.first.recent.length, 3); // 카드 콜라주용 최근 3장
    });
  });
}
