import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remine/data/device/local_db.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/models/category.dart';
import 'package:remine/models/screenshot_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        fileNamesOf: (ids) async {
          looked.addAll(ids);
          return {for (final id in ids) id: ?files[id]};
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

  test('OCR 기록의 파일명은 한 번의 쿼리로 묶어 읽는다(실제 SQLite, 기록 없는 id는 빠진다)', () async {
    final dir = await Directory.systemTemp.createTemp('remine_names');
    addTearDown(() => dir.delete(recursive: true));
    final db = LocalDb(
      path: p.join(dir.path, 'n.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close); // 나중에 등록한 것이 먼저 실행된다 → 닫고 나서 폴더를 지운다
    final store = SqfliteOcrStore(db);
    for (final (id, name) in [('a', 'A_NAVER.jpg'), ('b', 'B.jpg')]) {
      await store.save(
        OcrRecord(
          assetId: id,
          fileName: name,
          modifiedAt: 1,
          text: '',
          charCount: 0,
          ocrAt: DateTime(2026),
          engine: 'mlkit',
        ),
      );
    }

    expect(await store.fileNames(['a', 'b', 'x']), {
      'a': 'A_NAVER.jpg',
      'b': 'B.jpg',
    });
  });
}
