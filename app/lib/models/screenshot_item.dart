import 'category.dart';

/// GET /api/screenshots 의 항목. 필드 이름·타입은 서버 ScreenshotResponse와 같다.
///
/// [autoCategory], [categorySource]는 지금 서버의 목록 응답에는 없다(PATCH 응답에만 있음).
/// 수정 시트의 "AI는 X라고 했어요"에 필요해서 앱 모델에 두며, 3주차 연동 때 서버 목록 응답에 추가한다(spec 메모).
class ScreenshotItem {
  const ScreenshotItem({
    required this.id,
    required this.localAssetId,
    required this.takenAt,
    required this.category,
    required this.tags,
    this.sourceApp,
    this.summary,
    this.autoCategory,
    this.categorySource,
  });

  final int id;
  final String localAssetId;
  final DateTime takenAt;
  final String? sourceApp;
  final Category category;
  final String? summary;
  final List<String> tags;
  final Category? autoCategory;
  final CategorySource? categorySource;

  // [Dart 메모] factory 생성자는 JSON(Map) → 객체 변환에 흔히 쓴다. `as` 는 타입 단언(캐스팅)이다.
  factory ScreenshotItem.fromJson(Map<String, dynamic> json) => ScreenshotItem(
    id: (json['id'] as num).toInt(),
    localAssetId: json['localAssetId'] as String,
    takenAt: DateTime.parse(json['takenAt'] as String),
    sourceApp: json['sourceApp'] as String?,
    category: Category.fromJson(json['category'] as String),
    summary: json['summary'] as String?,
    tags: (json['tags'] as List).cast<String>(),
    autoCategory: json['autoCategory'] == null
        ? null
        : Category.fromJson(json['autoCategory'] as String),
    categorySource: json['categorySource'] == null
        ? null
        : CategorySource.fromJson(json['categorySource'] as String),
  );

  /// 불변 객체의 일부만 바꾼 복사본.
  ScreenshotItem copyWith({
    Category? category,
    CategorySource? categorySource,
  }) => ScreenshotItem(
    id: id,
    localAssetId: localAssetId,
    takenAt: takenAt,
    sourceApp: sourceApp,
    category: category ?? this.category,
    summary: summary,
    tags: tags,
    autoCategory: autoCategory,
    categorySource: categorySource ?? this.categorySource,
  );
}

/// GET /api/screenshots 의 페이지 응답 (서버 ScreenshotPageResponse).
class ScreenshotPage {
  const ScreenshotPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<ScreenshotItem> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory ScreenshotPage.fromJson(Map<String, dynamic> json) => ScreenshotPage(
    items: (json['items'] as List)
        .map((e) => ScreenshotItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    page: (json['page'] as num).toInt(),
    size: (json['size'] as num).toInt(),
    totalElements: (json['totalElements'] as num).toInt(),
    totalPages: (json['totalPages'] as num).toInt(),
  );
}
