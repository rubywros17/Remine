import 'package:flutter_test/flutter_test.dart';
import 'package:remine/core/helpers.dart';

void main() {
  test('촬영 시각은 "연.월.일 (요일)  |  시:분" 24시간제', () {
    expect(
      formatStamp(DateTime(2026, 11, 6, 13, 58)),
      '2026.11.06 (FRI)  |  13:58',
    );
    expect(
      formatStamp(DateTime(2026, 1, 5, 9, 3)),
      '2026.01.05 (MON)  |  09:03',
    );
  });
}
