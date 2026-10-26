import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remine/data/remote/api_client.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';

import 'support/fake_push.dart';
import 'support/fake_remote.dart';

/// 디버그 요청 로그: 요청마다 "메서드 경로 → 결과"만. 쿼리(태그)·헤더(기기 id)·본문(OCR·토큰)은 없다.
void main() {
  late List<String> lines;
  RemineApi api(RecordingClient client, {Duration? timeout}) => RemineApi(
    'http://localhost:8080',
    client,
    timeout: timeout ?? const Duration(minutes: 2),
    log: lines.add,
  );

  setUp(() => lines = []);

  test('메서드·경로·상태 코드만 찍고 쿼리·본문·헤더는 찍지 않는다', () async {
    final a = api(RecordingClient());

    await a.registerDevice('secret-fcm-token');
    await a.analyze(7, [
      AnalyzeItem(
        assetId: 'asset-1',
        takenAt: DateTime(2026, 10, 21),
        text: '비밀번호 1234567',
        image: Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    await expectLater(
      a.listJson(7, category: Category.shopping, tag: '신발'),
      throwsA(isA<ApiException>()), // 가짜 서버는 목록 경로를 모른다(404)
    );

    expect(lines, hasLength(3));
    expect(lines[0], startsWith('[api] POST /api/devices → 200 '));
    expect(lines[1], startsWith('[api] POST /api/screenshots/analyze → 200 '));
    expect(lines[2], startsWith('[api] GET /api/screenshots → 404 '));
    final all = lines.join('\n');
    for (final secret in [
      'secret-fcm-token',
      '1234567',
      'asset-1',
      '신발',
      'SHOPPING',
      '?',
      'X-Device-Id',
    ]) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
  });

  test('시간 초과·응답 없음도 한 줄로 남긴다', () async {
    final a = api(
      RecordingClient(
        responder: (r) => Completer<http.StreamedResponse>().future,
      ),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(a.config(), throwsA(isA<ApiException>()));

    expect(lines.single, startsWith('[api] GET /api/config → timeout '));
  });

  test('동기화가 멈추면 예외 종류만 남기고 메시지(OCR이 섞일 수 있음)는 남기지 않는다', () async {
    final rig = await SyncRig.create(
      photos: const [],
      push: FakePushClient(),
      client: RecordingClient()..throwOnSend = StateError('OCR 원문 비밀'),
      log: lines.add,
    );

    await rig.sync.run();

    expect(rig.status.issue, SyncIssue.internal); // 서버가 아니라 앱 안의 오류
    expect(lines, ['[sync] 중단: StateError']);
  });
}
