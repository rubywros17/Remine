import 'category.dart';

/// GET /api/categories/summary 의 항목 (서버 CategorySummaryResponse.Item).
class CategorySummaryItem {
  const CategorySummaryItem({
    required this.category,
    required this.count,
    required this.topTags,
    required this.recentAssetIds,
  });

  final Category category;
  final int count;
  final List<String> topTags;

  /// 카테고리별 최신 캡처의 localAssetId (최대 4개).
  final List<String> recentAssetIds;

  factory CategorySummaryItem.fromJson(Map<String, dynamic> json) =>
      CategorySummaryItem(
        category: Category.fromJson(json['category'] as String),
        count: (json['count'] as num).toInt(),
        topTags: (json['topTags'] as List).cast<String>(),
        recentAssetIds: (json['recentAssetIds'] as List).cast<String>(),
      );
}

/// GET /api/categories/summary 응답. 7개 카테고리가 모두 들어 있다(0장도 count 0).
class CategorySummary {
  const CategorySummary({required this.categories});

  final List<CategorySummaryItem> categories;

  factory CategorySummary.fromJson(Map<String, dynamic> json) =>
      CategorySummary(
        categories: (json['categories'] as List)
            .map((e) => CategorySummaryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get total => categories.fold(0, (sum, c) => sum + c.count);

  CategorySummaryItem of(Category category) =>
      categories.firstWhere((c) => c.category == category);

  /// 홈 알약·비율 막대 순서: 개수 내림차순, 같은 개수면 [Category] 고정 순서, 기타는 개수와 상관없이 맨 끝.
  ///
  /// [Dart 메모] `List.sort`는 같은 값의 순서를 보장하지 않으므로 동점 기준(enum `index`)을 직접 넣는다.
  List<CategorySummaryItem> get sortedForHome {
    int rank(CategorySummaryItem c) => c.category == Category.etc ? 1 : 0;
    return [...categories]..sort((a, b) {
      final byEtc = rank(a).compareTo(rank(b));
      if (byEtc != 0) return byEtc;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0
          ? byCount
          : a.category.index.compareTo(b.category.index);
    });
  }
}
