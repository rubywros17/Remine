/// 서버의 고정 카테고리 7개(spec 5장). [code]가 API의 문자열 값이다.
///
/// [Dart 메모] enum에 필드·생성자를 둘 수 있다(자바 enum과 같다). 순서는 서버 enum 순서와 같다.
enum Category {
  shopping('SHOPPING', '쇼핑'),
  entertainment('ENTERTAINMENT', '문화생활'),
  place('PLACE', '장소'),
  info('INFO', '정보'),
  chat('CHAT', '대화'),
  schedule('SCHEDULE', '일정'),
  etc('ETC', '기타');

  const Category(this.code, this.label);

  /// API 값 (예: "SHOPPING").
  final String code;

  /// 앱에 표시하는 이름.
  final String label;

  static Category fromJson(String code) => values.firstWhere(
    (c) => c.code == code,
    orElse: () => throw FormatException('알 수 없는 카테고리: $code'),
  );

  String toJson() => code;
}

/// category 값의 출처. AUTO는 모델 값 그대로, USER는 사용자가 지정·확인한 값.
enum CategorySource {
  auto('AUTO'),
  user('USER');

  const CategorySource(this.code);
  final String code;

  static CategorySource fromJson(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => throw FormatException('알 수 없는 출처: $code'),
  );
}
