import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';

ScreenshotItem _shot(int id, String assetId) => ScreenshotItem(
  id: id,
  localAssetId: assetId,
  takenAt: DateTime(2026, 11, 6, 13, id),
  category: Category.shopping,
  tags: const [],
);

void main() {
  test(
    '출처는 기기 파일명의 앱 이름(대문자)으로 채우고, 이름 없는 캡처는 비우며, 한 번 찾은 건 다시 찾지 않는다',
    () async {
      final files = {
        'a': 'Screenshot_20261106_135800_Instagram.jpg',
        'b': 'Screenshot_20261106_135900.jpg', // 앱 이름 없음
      };
      final looked = <String>[];
      final repo = LocalMergedRepository(
        FakeScreenshotRepository(seed: [_shot(1, 'a'), _shot(2, 'b')]),
        InMemoryLocalVerdictStore(),
        fileNameOf: (id) async {
          looked.add(id);
          return files[id];
        },
      );

      final first = await repo.list();
      final byAsset = {
        for (final s in first.items) s.localAssetId: s.sourceApp,
      };
      expect(byAsset, {'a': 'INSTAGRAM', 'b': null});

      await repo.list();
      expect(looked..sort(), ['a', 'b']); // 두 번째 목록은 캐시만 쓴다
    },
  );
}
