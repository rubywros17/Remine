import 'package:flutter_test/flutter_test.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/interest.dart';

Interest _i(
  String tag, {
  int count = 3,
  int dormant = 1,
  bool forgotten = false,
}) => Interest(
  tag: tag,
  category: Category.etc,
  forgotten: forgotten,
  captureCount: count,
  dormantDays: dormant,
  peakMonth: 9,
  peakMonthCount: count,
  latestMonth: 11,
  latestMonthCount: count,
  recent: const [],
);

void main() {
  test('빈 목록이면 null', () {
    expect(pickHomeInterest(const []), isNull);
  });

  test('잊은 관심사가 앞에 있어도 요즘 모으는 중에서 장수가 가장 많은 것', () {
    final list = [
      _i('필기구', count: 3, dormant: 40, forgotten: true),
      _i('네일아트', count: 17),
      _i('뜨개질', count: 38, dormant: 5),
    ];
    expect(pickHomeInterest(list)!.tag, '뜨개질');
  });

  test('장수가 같으면 최근에 캡처한 것', () {
    final list = [
      _i('캠핑', count: 5, dormant: 9),
      _i('향수', count: 5, dormant: 2),
    ];
    expect(pickHomeInterest(list)!.tag, '향수');
  });

  test('요즘 것이 없으면 목록 첫 번째(잊고 있었던 관심사 1등)', () {
    final list = [
      _i('필기구', count: 9, dormant: 40, forgotten: true),
      _i('코바늘도안', count: 20, dormant: 60, forgotten: true),
    ];
    expect(pickHomeInterest(list)!.tag, '필기구');
  });
}
