import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/remote/api_client.dart';
import 'package:remine/data/remote/remote_repository.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';
import 'package:http/http.dart' as http;

import 'support/fake_remote.dart';

Map<String, dynamic> _item(int id, String asset, String category) => {
  'id': id,
  'localAssetId': asset,
  'takenAt': '2026-10-21T12:00:00',
  'sourceApp': null,
  'category': category,
  'autoCategory': 'INFO',
  'categorySource': 'AUTO',
  'summary': '요약',
  'tags': ['태그'],
};

Map<String, dynamic> _summary(int shopping) => {
  'categories': [
    for (final c in Category.values)
      {
        'category': c.code,
        'count': c == Category.shopping ? shopping : 0,
        'topTags': <String>[],
        'recentAssetIds': <String>[],
      },
  ],
};

void main() {
  late RecordingClient client;
  late InMemoryRemoteStateStore state;
  late SyncStatus status;
  late RemoteRepository repo;
  var online = true;

  setUp(() async {
    online = true;
    late final RecordingClient c;
    c = RecordingClient(
      responder: (r) {
        if (!online) throw http.ClientException('down');
        if (r.path == '/api/screenshots') {
          return jsonResponse({
            'items': [_item(5, 'a5', 'SHOPPING'), _item(6, 'a6', 'INFO')],
            'page': 0,
            'size': 30,
            'totalElements': 2,
            'totalPages': 1,
          });
        }
        if (r.path == '/api/categories/summary') {
          return jsonResponse(_summary(2));
        }
        if (r.path.endsWith('/category')) {
          return jsonResponse({
            'id': 5,
            'category': 'PLACE',
            'autoCategory': 'SHOPPING',
            'categorySource': 'USER',
          });
        }
        return c.defaultFor(r);
      },
    );
    client = c;
    state = InMemoryRemoteStateStore();
    await state.setDeviceId(7);
    status = SyncStatus();
    repo = RemoteRepository(
      RemineApi('http://localhost:8080', client),
      state,
      status,
    );
  });

  test('목록·요약을 받아 보여 주고 asset id ↔ 서버 id 매핑을 채운다', () async {
    await state.putEntry(
      const SyncEntry(
        assetId: 'a5',
        modifiedAt: 1,
        status: SyncStatusCode.synced,
      ),
    );
    final page = await repo.list();
    expect(page.items.map((i) => i.id), [5, 6]);
    expect(page.items.first.autoCategory, Category.info);
    expect(page.items.first.categorySource?.code, 'AUTO');
    expect((await repo.summary()).of(Category.shopping).count, 2);
    expect((await state.entry('a5'))?.serverId, 5);
  });

  test('서버가 꺼져 있으면 마지막으로 받은 목록·요약을 보여 주고 안내 상태가 된다', () async {
    await repo.list();
    await repo.summary();
    online = false;

    final page = await repo.list();
    final summary = await repo.summary();

    expect(page.items.map((i) => i.id), [5, 6]);
    expect(summary.of(Category.shopping).count, 2);
    expect(status.issue, SyncIssue.offline);

    online = true;
    await repo.summary();
    expect(status.issue, SyncIssue.none, reason: '다시 연결되면 안내가 사라진다');
  });

  test('받아 둔 게 없으면 빈 목록과 0장 요약이고 앱이 죽지 않는다', () async {
    online = false;

    expect((await repo.list()).items, isEmpty);
    final summary = await repo.summary();
    expect(summary.categories, hasLength(Category.values.length));
    expect(summary.total, 0);
    expect(status.issue, SyncIssue.offline);
  });

  test('기기 등록 전(id 없음)에는 서버를 부르지 않고 빈 결과', () async {
    final fresh = RemoteRepository(
      RemineApi('http://localhost:8080', client),
      InMemoryRemoteStateStore(),
      status,
    );
    expect((await fresh.list()).items, isEmpty);
    expect(client.sent, isEmpty);
  });

  test('카테고리 수정은 PATCH로 보내고, 서버에 못 닿으면 예외로 알린다', () async {
    final ok = await repo.updateCategory(5, Category.place);
    expect(ok.categorySource.code, 'USER');
    expect(client.sent.last.method, 'PATCH');
    expect(client.sent.last.path, '/api/screenshots/5/category');
    expect(client.sent.last.utf8Text, contains('"PLACE"'));

    online = false;
    await expectLater(
      repo.updateCategory(5, Category.info),
      throwsA(isA<ApiException>()),
    );
  });

  test('휴지통에 넣은 서버 캡처는 목록과 요약 개수에서 빠진다', () async {
    await repo.list();
    await repo.trash(5);

    expect((await repo.list()).items.map((i) => i.id), [6]);
    expect((await repo.summary()).of(Category.shopping).count, 1);
    await repo.restore(5);
    expect((await repo.list()).items, hasLength(2));
  });
}
