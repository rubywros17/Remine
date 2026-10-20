import 'category.dart';

/// PATCH /api/screenshots/{id}/category 응답 (서버 CategoryUpdateResponse).
class CategoryUpdate {
  const CategoryUpdate({
    required this.id,
    required this.category,
    required this.autoCategory,
    required this.categorySource,
  });

  final int id;
  final Category category;

  /// 모델이 처음 낸 값(불변).
  final Category autoCategory;
  final CategorySource categorySource;

  factory CategoryUpdate.fromJson(Map<String, dynamic> json) => CategoryUpdate(
    id: (json['id'] as num).toInt(),
    category: Category.fromJson(json['category'] as String),
    autoCategory: Category.fromJson(json['autoCategory'] as String),
    categorySource: CategorySource.fromJson(json['categorySource'] as String),
  );
}
