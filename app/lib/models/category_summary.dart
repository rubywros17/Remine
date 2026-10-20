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

  factory CategorySummaryItem.fromJson(Map<String, dynamic> json) => CategorySummaryItem(
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

  factory CategorySummary.fromJson(Map<String, dynamic> json) => CategorySummary(
        categories: (json['categories'] as List)
            .map((e) => CategorySummaryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get total => categories.fold(0, (sum, c) => sum + c.count);

  CategorySummaryItem of(Category category) => categories.firstWhere((c) => c.category == category);

  /// 홈 알약 순서: 개수 내림차순, 기타는 항상 마지막(같은 개수면 서버 순서 유지).
  List<CategorySummaryItem> get sortedForHome {
    final list = [...categories];
    list.sort((a, b) {
      if (a.category == Category.etc) return b.category == Category.etc ? 0 : 1;
      if (b.category == Category.etc) return -1;
      return b.count.compareTo(a.count);
    });
    return list;
  }

  /// 개수가 가장 많은 카테고리(0장뿐이면 null). 홈에서 셀라돈으로 채운다.
  Category? get largest {
    final nonEmpty = categories.where((c) => c.count > 0).toList();
    if (nonEmpty.isEmpty) return null;
    nonEmpty.sort((a, b) => b.count.compareTo(a.count));
    return nonEmpty.first.category;
  }
}
