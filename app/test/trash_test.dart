import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:remine/data/device/device_trash.dart';
import 'package:remine/data/device/local_db.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/trash_store.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/data/remote/remote_state_store.dart';
import 'package:remine/models/category.dart';
import 'package:remine/screens/trash_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_device.dart';
import 'support/fake_remote.dart';

TrashedShot _shot(
  String id, {
  bool onServer = true,
  int minutes = 0,
  Category category = Category.shopping,
}) => TrashedShot(
  assetId: id,
  category: category,
  takenAt: DateTime(2026, 11, 1),
  trashedAt: DateTime(2026, 11, 5, 12, minutes),
  onServer: onServer,
);

Iterable<String> _idsSentTo(RecordingClient client, String path) => client.sent
    .where((r) => r.path == path)
    .expand(
      (r) =>
          (jsonDecode(utf8.decode(r.body))['assetIds'] as List).cast<String>(),
    );

void main() {
  group('SqfliteTrashStore', () {
    sqfliteFfiInit();
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('remine_trash_');
      path = p.join(dir.path, 'remine_ocr.db');
    });
    tearDown(() => dir.delete(recursive: true));

    LocalDb open() => LocalDb(path: path, factory: databaseFactoryFfi);

    test('앱을 다시 켜도 휴지통과 서버 반영 대기가 남는다', () async {
      final first = open();
      await SqfliteTrashStore(first).add(_shot('a1'));
      await SqfliteTrashStore(first)
          .add(_shot('d1', onServer: false, minutes: 1));
      await first.close();

      final again = open();
      final store = SqfliteTrashStore(again);
      expect((await store.all()).map((s) => s.assetId), [
        'd1',
        'a1',
      ], reason: '최신순');
      expect((await store.outbox()).trash, ['a1'], reason: '기기 전용은 서버에 안 보낸다');
      await again.close();
    });

    test('v3 DB를 올리면 trash 표가 생기고 기존 표는 그대로다', () async {
      final v3 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await db.insert('setting', {'key': 'k', 'value': 'v'});
          },
        ),
      );
      await v3.close();

      final local = open();
      await SqfliteTrashStore(local).add(_shot('a1'));
      expect(await SqfliteTrashStore(local).all(), hasLength(1));
      final rows = await (await local.db).query('setting');
      expect(rows.single['value'], 'v');
      await local.close();
    });

    test('되살리기·갤러리 삭제의 대기와 상태 변화', () async {
      final local = open();
      await _storeContract(() async => SqfliteTrashStore(local));
      await local.close();
    });
  });

  group('InMemoryTrashStore', () {
    test(
      'Sqflite 구현과 같은 약속',
      () => _storeContract(() async => InMemoryTrashStore()),
    );
  });

  group('서버 반영', () {
    Future<SyncRig> rig({RecordingClient? client}) async {
      final r = await SyncRig.create(
        photos: fakePhotos(1),
        texts: {'p0': '글자 ' * 60},
        client: client,
      );
      await r.state.setDeviceId(7);
      return r;
    }

    test('대기열을 보내고, 되살리기는 restore로 보낸다', () async {
      final r = await rig();
      await r.trash.add(_shot('a1'));
      await r.sync.flushTrash();
      expect(_idsSentTo(r.client, '/api/screenshots/trash'), ['a1']);
      expect((await r.trash.outbox()).isEmpty, isTrue);

      await r.trash.restore('a1');
      expect(await r.trash.all(), isEmpty, reason: '목록에서는 바로 빠진다');
      await r.sync.flushTrash();
      expect(_idsSentTo(r.client, '/api/screenshots/restore'), ['a1']);
      expect((await r.trash.outbox()).isEmpty, isTrue);
    });

    test('네트워크 실패면 로컬에 남고 다음 동기화 때 다시 보낸다', () async {
      final r = await rig();
      await r.trash.add(_shot('a1'));

      r.client.throwOnSend = const SocketException('없음');
      await r.sync.flushTrash();
      expect(await r.trash.all(), hasLength(1), reason: '휴지통은 그대로');
      expect((await r.trash.outbox()).trash, ['a1'], reason: '대기 유지');

      r.client.throwOnSend = null;
      await r.sync.run();
      expect(_idsSentTo(r.client, '/api/screenshots/trash'), contains('a1'));
      expect((await r.trash.outbox()).isEmpty, isTrue);
    });

    test('서버 오류(500)도 대기로 남는다', () async {
      final r = await rig(
        client: RecordingClient(
          responder: (req) => req.path == '/api/screenshots/trash'
              ? http.StreamedResponse(const Stream.empty(), 500)
              : RecordingClient().defaultFor(req),
        ),
      );
      await r.trash.add(_shot('a1'));
      await r.sync.flushTrash();
      expect((await r.trash.outbox()).trash, ['a1']);
    });

    test('옛 서버의 404는 대기로 남고 기기를 재등록하지 않는다', () async {
      final r = await rig(
        client: RecordingClient(
          responder: (req) => req.path == '/api/screenshots/trash'
              ? http.StreamedResponse(const Stream.empty(), 404)
              : RecordingClient().defaultFor(req),
        ),
      );
      await r.trash.add(_shot('a1'));
      await r.sync.flushTrash();
      expect((await r.trash.outbox()).trash, ['a1']);
      expect(r.client.sent.where((s) => s.path == '/api/devices'), isEmpty);
    });

    test('기기 전용 캡처는 어떤 요청에도 asset id가 실리지 않는다', () async {
      final r = await rig();
      await r.trash.add(_shot('secret-asset', onServer: false));
      await r.sync.flushTrash();
      await r.trash.restore('secret-asset');
      await r.sync.flushTrash();
      for (final s in r.client.sent) {
        expect(
          utf8.decode(s.body, allowMalformed: true),
          isNot(contains('secret-asset')),
        );
      }
    });

    test('500장 넘으면 나눠 보낸다', () async {
      final r = await rig();
      for (var i = 0; i < 501; i++) {
        await r.trash.add(_shot('a$i'));
      }
      await r.sync.flushTrash();
      final calls = r.client.sent.where(
        (s) => s.path == '/api/screenshots/trash',
      );
      expect(calls, hasLength(2));
      expect(_idsSentTo(r.client, '/api/screenshots/trash'), hasLength(501));
    });

    test('재등록하면 휴지통 표시를 다시 보낸다', () async {
      final store = InMemoryTrashStore();
      await store.add(_shot('a1'));
      await store.trashSent(['a1']);
      expect((await store.outbox()).isEmpty, isTrue);
      await store.resendAll();
      expect((await store.outbox()).trash, ['a1']);
    });
  });

  group('목록·요약에서 빠지기', () {
    Future<(SyncRig, int)> withItem() async {
      final r = await SyncRig.create(
        photos: const [],
        client: RecordingClient(
          responder: (req) =>
              req.path == '/api/screenshots' && req.method == 'GET'
              ? jsonResponse({
                  'items': [
                    {
                      'id': 5,
                      'localAssetId': 'a5',
                      'takenAt': '2026-11-01T10:00:00',
                      'category': 'SHOPPING',
                      'autoCategory': 'SHOPPING',
                      'categorySource': 'AUTO',
                      'tags': <String>[],
                    },
                  ],
                  'page': 0,
                  'size': 30,
                  'totalElements': 1,
                  'totalPages': 1,
                })
              : RecordingClient().defaultFor(req),
        ),
      );
      await r.state.setDeviceId(7);
      await r.repository.list();
      return (r, 5);
    }

    test('스와이프하면 목록에서 빠지고 서버 응답을 기다리지 않으며, 되살리면 돌아온다', () async {
      final (r, id) = await withItem();
      await r.repository.trash(id);
      expect((await r.repository.list()).items, isEmpty);
      expect((await r.trash.all()).single.assetId, 'a5');
      await r.sync.flushTrash();
      expect(_idsSentTo(r.client, '/api/screenshots/trash'), ['a5']);

      await r.repository.restore(id);
      expect((await r.repository.list()).items, hasLength(1));
    });

    test('갤러리에서 지웠는데 서버에서 아직 못 지웠어도 목록에 안 나온다', () async {
      final (r, id) = await withItem();
      // 서버 알림 없이 대기열에만 둔다(서버가 아직 그 캡처를 돌려주는 상황).
      expect(id, 5);
      await r.trash.add(_shot('a5'));
      await r.trash.markDeleted(['a5']);
      expect(await r.trash.all(), isEmpty);
      expect((await r.repository.list()).items, isEmpty);
    });

    test('기기에서 분류한 캡처도 휴지통에 남고 서버 대기는 없다', () async {
      final verdicts = InMemoryLocalVerdictStore();
      await verdicts.save(
        StoredVerdict(
          localId: 0,
          assetId: 'm1',
          takenAt: DateTime(2026, 11, 1),
          modifiedAt: 1,
          route: LocalRoute.deviceOnly,
          category: Category.chat,
          hidden: false,
          reasons: const [],
          decidedAt: DateTime(2026, 11, 1),
        ),
      );
      final r = await SyncRig.create(photos: const []);
      final merged = LocalMergedRepository(
        r.repository,
        verdicts,
        trash: r.trash,
      );
      final item = (await merged.list()).items.single;
      expect(item.id, isNegative);

      await merged.trash(item.id);
      expect((await merged.list()).items, isEmpty);
      expect((await r.trash.all()).single.onServer, isFalse);
      expect((await r.trash.outbox()).isEmpty, isTrue);

      await merged.restore(item.id);
      expect((await merged.list()).items, hasLength(1));
    });
  });

  group('갤러리에서 삭제', () {
    late FakeGalleryReader reader;
    late InMemoryTrashStore store;
    late InMemoryLocalVerdictStore verdicts;
    late InMemoryOcrStore ocr;
    late InMemoryRemoteStateStore state;
    late DeviceTrash trash;
    var flushed = 0;

    setUp(() async {
      reader = FakeGalleryReader();
      store = InMemoryTrashStore();
      verdicts = InMemoryLocalVerdictStore();
      ocr = InMemoryOcrStore();
      state = InMemoryRemoteStateStore();
      flushed = 0;
      trash = DeviceTrash(
        store: store,
        reader: reader,
        verdicts: verdicts,
        ocr: ocr,
        onChanged: () async => flushed++,
        forgetEntries: state.removeEntries,
      );
      await store.add(_shot('a1'));
      await store.trashSent(['a1']);
      await store.add(_shot('d1', onServer: false));
      await state.putEntry(
        const SyncEntry(
          assetId: 'a1',
          modifiedAt: 1,
          status: SyncStatusCode.synced,
        ),
      );
    });

    test('확인창은 한 번이고, 허용하면 앱 기록을 지우고 서버 삭제를 대기시킨다', () async {
      expect(await trash.deleteFromGallery(['a1', 'd1']), 2);

      expect(reader.trashRequests, [
        ['a1', 'd1'],
      ], reason: '시스템 확인창 1회');
      expect(await store.all(), isEmpty);
      expect((await store.outbox()).forget, ['a1'], reason: '서버 캡처만');
      expect(await state.entry('a1'), isNull);
      expect(flushed, 1);
    });

    test('취소하면 아무것도 바뀌지 않는다', () async {
      reader.allowTrash = false;
      expect(await trash.deleteFromGallery(['a1', 'd1']), 0);

      expect(await store.all(), hasLength(2));
      expect((await store.outbox()).forget, isEmpty);
      expect(await state.entry('a1'), isNotNull);
      expect(flushed, 0);
    });
  });

  group('휴지통 화면', () {
    late FakeGalleryReader reader;
    late InMemoryTrashStore store;

    Future<void> show(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final services = fakeServices(reader, trash: store);
      await tester.pumpWidget(
        MaterialApp(home: TrashScreen(trash: services.trash)),
      );
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(find.text(text).first);
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    setUp(() {
      reader = FakeGalleryReader();
      store = InMemoryTrashStore();
    });

    testWidgets('비어 있으면 안내만 나오고 [전체 선택]도 숨긴다', (tester) async {
      await show(tester);
      expect(find.text('휴지통 0장'), findsOneWidget);
      expect(find.text('삭제한 스크린샷이 없어요'), findsOneWidget);
      expect(find.text('전체 선택'), findsNothing);
      expect(find.text('갤러리에서도 삭제'), findsNothing, reason: '위쪽 삭제 버튼은 없앴다');
    });

    testWidgets('버린 날짜 최신순, 고르면 하단 바에 [복구]·[삭제 N장]', (tester) async {
      await store.add(_shot('old'));
      await store.add(_shot('new', minutes: 5));
      await show(tester);

      expect(find.text('휴지통 2장'), findsOneWidget);
      expect(find.text(trashGalleryNote), findsOneWidget);
      expect(find.text('복구'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('trash-new'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('trash-old'))).dx),
      );

      await tester.tap(find.byKey(const ValueKey('trash-old')));
      await tester.pump();
      expect(find.text('복구'), findsOneWidget);
      expect(find.text('삭제 1장'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('trash-new')));
      await tester.pump();
      expect(find.text('삭제 2장'), findsOneWidget);
    });

    testWidgets('[전체 선택] → 모두 고르면 [선택 해제], 누르면 다시 비운다', (tester) async {
      await store.add(_shot('a1'));
      await store.add(_shot('a2', minutes: 1));
      await show(tester);

      await tester.tap(find.text('전체 선택'));
      await tester.pump();
      expect(find.text('선택 해제'), findsOneWidget);
      expect(find.text('전체 선택'), findsNothing);
      expect(find.text('삭제 2장'), findsOneWidget);

      await tester.tap(find.text('선택 해제'));
      await tester.pump();
      expect(find.text('전체 선택'), findsOneWidget);
      expect(find.text('복구'), findsNothing, reason: '고른 게 없으면 하단 바도 없다');

      // 하나씩 다 골라도 [선택 해제]가 된다.
      await tester.tap(find.byKey(const ValueKey('trash-a1')));
      await tester.tap(find.byKey(const ValueKey('trash-a2')));
      await tester.pump();
      expect(find.text('선택 해제'), findsOneWidget);
    });

    testWidgets('[복구]는 고른 장만 되살린다', (tester) async {
      await store.add(_shot('a1'));
      await store.add(_shot('a2', minutes: 1));
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('trash-a1')));
      await tester.pump();

      await tapText(tester, '복구');

      expect(find.text('휴지통 1장'), findsOneWidget);
      expect((await store.all()).single.assetId, 'a2');
      expect(find.text('복구'), findsNothing);
    });

    testWidgets('[전체 선택] 후 [삭제 N장]은 전체를 한 번에 요청한다', (tester) async {
      await store.add(_shot('a1'));
      await store.add(_shot('a2', minutes: 1));
      await show(tester);

      await tester.tap(find.text('전체 선택'));
      await tester.pump();
      await tapText(tester, '삭제 2장');

      expect(reader.trashRequests.single, ['a2', 'a1'], reason: '시스템 확인창 1회');
      expect(find.text('삭제한 스크린샷이 없어요'), findsOneWidget);
    });

    testWidgets('[삭제 N장]은 고른 장만 요청한다', (tester) async {
      await store.add(_shot('a1'));
      await store.add(_shot('a2', minutes: 1));
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('trash-a1')));
      await tester.pump();

      await tapText(tester, '삭제 1장');

      expect(reader.trashRequests.single, ['a1']);
      expect((await store.all()).single.assetId, 'a2');
    });

    testWidgets('확인창을 취소하면 그대로다', (tester) async {
      reader.allowTrash = false;
      await store.add(_shot('a1'));
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('trash-a1')));
      await tester.pump();

      await tapText(tester, '삭제 1장');

      expect(find.text('휴지통 1장'), findsOneWidget);
      expect(await store.all(), hasLength(1));
    });

    testWidgets('Android 10 이하는 [삭제] 없이 [복구]만 된다', (tester) async {
      reader.trashSupported = false;
      await store.add(_shot('a1'));
      await show(tester);
      expect(find.text(trashGalleryNote), findsNothing);
      expect(find.text('전체 선택'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('trash-a1')));
      await tester.pump();
      expect(find.text('복구'), findsOneWidget);
      expect(find.textContaining('삭제 '), findsNothing);
    });

    for (final (size, scale) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
      (Size(240, 320), 1.0),
      (Size(412, 915), 1.3),
    ]) {
      testWidgets('넘치지 않는다 $size ×$scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (var i = 0; i < 30; i++) {
          await store.add(_shot('a$i', minutes: i));
        }
        await show(tester, size: size);
        await tester.tap(find.byKey(const ValueKey('trash-a29')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _storeContract(Future<TrashStore> Function() make) async {
  final s = await make();
  await s.add(_shot('keep'));
  await s.add(_shot('back'));
  await s.add(_shot('gone'));
  await s.add(_shot('local', onServer: false));
  await s.trashSent(['keep', 'back', 'gone']);
  expect((await s.outbox()).isEmpty, isTrue);

  await s.restore('back');
  await s.markDeleted(['gone', 'local']);

  expect((await s.all()).map((t) => t.assetId), ['keep']);
  expect((await s.hidden()).map((t) => t.assetId).toSet(), {'keep', 'gone'});
  final o = await s.outbox();
  expect(o.restore, ['back']);
  expect(o.forget, ['gone']);
  expect(o.trash, isEmpty);

  await s.restoreSent(['back']);
  await s.forgetSent(['gone']);
  expect((await s.outbox()).isEmpty, isTrue);
  expect((await s.hidden()).map((t) => t.assetId), ['keep']);

  // 보내는 사이 되살렸으면, 늦게 온 trashSent가 restore 대기를 지우지 않는다.
  await s.add(_shot('race'));
  await s.restore('race');
  await s.trashSent(['race']);
  expect((await s.outbox()).restore, contains('race'));
}
