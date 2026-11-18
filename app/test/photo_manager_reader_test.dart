import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:remine/data/device/photo_manager_gallery_reader.dart';

// 실제 PhotoManagerGalleryReader를 photo_manager 채널을 흉내 낸 가짜 기기로 돌린다.
// 실기기에서 난 "[sync] 중단: StateError"(기기 등록 뒤 새 스크린샷 0장일 때 photo_manager가 던짐)와
// 커서 상한이 "지금"으로 덮여 예전 스크린샷이 앞쪽만 되풀이되던 문제를 막는다.

const _channel = MethodChannel('com.fluttercandies/photo_manager');

/// 앨범 하나(`shots`)와 사진들. 조건(생성 시각 min·max)에 맞는 사진이 0장이면 경로 조회에 null을 돌려준다
/// — 그러면 photo_manager가 StateError를 던진다(실기기와 같은 동작).
class _FakeNative {
  _FakeNative(this.secondsById);

  /// id → 생성 시각(epoch 초). 최신순 정렬은 여기서 한다.
  final Map<String, int> secondsById;
  final List<Map<String, dynamic>> pathOptions = [];

  List<String> _matching(Map<dynamic, dynamic>? option) {
    // FilterOptionGroup.toMap() = {type, child: {createDate: {min, max, ignore}, …}}
    final child = option?['child'] as Map<dynamic, dynamic>?;
    final cond = child?['createDate'] as Map<dynamic, dynamic>?;
    final min = (cond?['min'] as int?) ?? 0;
    final max = (cond?['max'] as int?) ?? 1 << 62;
    final ids =
        secondsById.entries
            .where((e) => e.value * 1000 >= min && e.value * 1000 <= max)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ids) e.key];
  }

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    final option = args['option'] as Map<dynamic, dynamic>?;
    switch (call.method) {
      case 'fetchPathProperties':
        pathOptions.add(Map<String, dynamic>.from(option ?? const {}));
        final n = _matching(option).length;
        if (n == 0) return null;
        return {
          'data': [
            {
              'id': 'shots',
              'name': 'Screenshots',
              'assetCount': n,
              'isAll': false,
            },
          ],
        };
      case 'getAssetCountFromPath':
        return _matching(option).length;
      case 'getAssetListRange':
        final ids = _matching(option);
        final start = args['start'] as int;
        final end = (args['end'] as int).clamp(0, ids.length);
        return {
          'data': [
            for (final id in ids.sublist(start, end))
              {
                'id': id,
                'type': 1,
                'width': 1080,
                'height': 2340,
                'title': 'Screenshot_$id.jpg',
                'createDt': secondsById[id],
                'modifiedDt': secondsById[id],
              },
          ],
        };
      default:
        return null;
    }
  }
}

int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeNative native;
  final base = DateTime(2026, 10, 19, 12);

  setUp(() {
    // p0이 가장 최신, 1분 간격으로 오래됨
    native = _FakeNative({
      for (var i = 0; i < 30; i++)
        'p$i': _sec(base.subtract(Duration(minutes: i))),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  final reader = PhotoManagerGalleryReader();

  test('기기 등록 뒤 새 스크린샷이 0장이면 StateError 대신 빈 목록', () async {
    expect(
      await reader.since('shots', base.add(const Duration(hours: 1))),
      isEmpty,
    );
  });

  test('등록 뒤 사진은 개수 제한 없이 최신순으로 읽는다', () async {
    final photos = await reader.since(
      'shots',
      base.subtract(const Duration(minutes: 2)),
    );
    expect(photos.map((p) => p.id), ['p0', 'p1', 'p2']);
    expect(photos.first.createdAt, base);
  });

  test('커서보다 오래된 쪽을 차례로 읽는다(상한이 "지금"으로 덮이지 않는다)', () async {
    final first = await reader.olderThan('shots', null, limit: 5);
    expect(first.map((p) => p.id), ['p0', 'p1', 'p2', 'p3', 'p4']);

    final next = await reader.olderThan('shots', first.last.position, limit: 5);
    expect(next.map((p) => p.id), ['p5', 'p6', 'p7', 'p8', 'p9']);
    final max = native.pathOptions.last['child']['createDate']['max'] as int;
    expect(
      max,
      lessThan(base.millisecondsSinceEpoch),
      reason: '커서 상한이 그대로 전달된다',
    );
  });

  test('범위 시작보다 오래된 사진은 읽지 않고, 다 읽으면 빈 목록', () async {
    final from = base.subtract(const Duration(minutes: 3));
    final photos = await reader.olderThan(
      'shots',
      null,
      notBefore: from,
      limit: 10,
    );
    expect(photos.map((p) => p.id), ['p0', 'p1', 'p2', 'p3']);
    expect(
      await reader.olderThan(
        'shots',
        photos.last.position,
        notBefore: from,
        limit: 10,
      ),
      isEmpty,
    );
  });

  test('앨범이 비어 있어도 최근 목록은 빈 목록', () async {
    native.secondsById.clear();
    expect(await reader.recent('shots'), isEmpty);
  });

  test('photo_manager는 사진 0장 조건에서 StateError를 던진다(이 리더가 막는 동작)', () async {
    native.secondsById.clear();
    await expectLater(
      // 리더를 거치지 않은 원래 호출(고치기 전 since가 이렇게 불렀다)
      () => AssetPathEntity.fromId(
        'shots',
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          createTimeCond: DateTimeCond(min: base, max: DateTime(2100)),
        ),
      ),
      throwsStateError,
    );
  });
}
