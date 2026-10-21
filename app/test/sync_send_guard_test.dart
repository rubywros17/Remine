import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/remote/api_client.dart';
import 'package:remine/data/remote/jpeg_guard.dart';
import 'package:remine/data/remote/sync_status.dart';
import 'package:remine/models/category.dart';

import 'support/fake_remote.dart';

// 보내면 안 되는 캡처가 HTTP 요청 본문(가짜 클라이언트가 기록한 바이트 전체)에 절대 실리지 않는지 검사한다.
const _card = '4111 1111 1111 1111';
const _phone = '010-1234-5678';
const _longText =
    '서울 성수동 팝업스토어 오픈 안내 운영 시간 열한 시부터 여덟 시까지 주말에는 줄이 길어서 평일 방문을 추천해요 '
    '주소는 성수이로 이십 길 입장은 무료이고 사전 예약은 필요하지 않아요 주차는 근처 공영주차장을 이용해 주세요 '
    '굿즈는 현장 구매만 가능합니다 영업시간과 메뉴 가격은 매장 사정에 따라 바뀔 수 있으니 방문 전에 확인해 주세요 '
    '근처 카페와 식당도 함께 둘러보기 좋아요';
const _shortText = '짧은 글';

void main() {
  late SyncRig rig;

  Future<SyncRig> build(
    Map<String, String> fileNames,
    Map<String, String> texts, {
    bool? consent = true,
  }) => SyncRig.create(
    photos: photosNamed(fileNames),
    texts: texts,
    consent: consent,
  );

  /// 모든 요청 본문을 이어 붙인 글자(바이너리는 latin1, JSON 한글은 UTF-8 쪽도 함께 본다).
  String allBodies() =>
      rig.client.sent.map((r) => '${r.text}\n${r.utf8Text}').join('\n');

  group('보내면 안 되는 캡처', () {
    test('메신저·금융 앱 파일명은 OCR도, 전송도 하지 않는다', () async {
      rig = await build(
        {
          'chat1': 'Screenshot_20261021_101010_KakaoTalk.jpg',
          'bank1': 'Screenshot_20261021_101011_Toss.jpg',
          'ok1': 'Screenshot_20261021_101012_Chrome.jpg',
        },
        {'chat1': '대화 내용 비밀', 'bank1': '잔액 1,000원', 'ok1': _longText},
      );
      await rig.sync.run();

      final body = allBodies();
      expect(body, isNot(contains('chat1')));
      expect(body, isNot(contains('bank1')));
      expect(body, isNot(contains('대화 내용 비밀')));
      expect(body, isNot(contains('잔액')));
      expect(body, contains('ok1')); // 일반 캡처는 보낸다
      expect(rig.ocr.recognized, isNot(contains('chat1')));
    });

    test('강한 민감 정보(카드번호)가 보이는 캡처는 텍스트도 이미지도 보내지 않는다', () async {
      rig = await build(
        {'card1': 'a.jpg', 'ok1': 'b.jpg'},
        {'card1': '결제 카드 $_card 유효기간', 'ok1': _longText},
      );
      await rig.sync.run();

      final body = allBodies();
      expect(body, isNot(contains('card1')));
      expect(body, isNot(contains('4111')));
      expect(body, isNot(contains('결제 카드')));
      final v = await rig.capture.verdicts.find('card1');
      expect(v?.route, LocalRoute.deviceOnly); // 기기에서 ETC로 정해졌다
    });

    test('전화번호 캡처는 가린 텍스트만 가고, 글자가 적고 동의가 켜져 있어도 이미지는 없다', () async {
      rig = await build(
        {'tel1': 'a.jpg'},
        {'tel1': '맛집 전화 $_phone'}, // 글자 수 < 150 + 동의 켜짐
      );
      await rig.sync.run();

      final calls = rig.client.analyzeCalls.toList();
      expect(calls, hasLength(1));
      expect(calls.single.isMultipart, isFalse, reason: '이미지 파트가 있으면 안 된다');
      final body = allBodies();
      expect(body, isNot(contains('1234')));
      expect(body, isNot(contains('010')));
      expect(body, contains('[전화번호]'));
      expect(rig.shrinker.calls, isEmpty, reason: '이미지를 만들지도 않는다');
    });

    test('파일명과 앱 이름은 어떤 요청에도 실리지 않는다(asset id와 촬영 시각만)', () async {
      rig = await build(
        {
          'p1': 'Screenshot_20261021_101012_Instagram.jpg',
          'p2': 'Screenshot_20261021_101013_Chrome.jpg',
        },
        {'p1': _longText, 'p2': _shortText},
      );
      await rig.sync.run();

      final body = allBodies();
      expect(body, isNot(contains('Screenshot_')));
      expect(body, isNot(contains('Instagram')));
      expect(body, isNot(contains('Chrome')));
      expect(body, isNot(contains('101012'))); // 파일명 속 시각
      expect(body, isNot(contains('101013')));
      expect(body, isNot(contains('sourceApp')));
      final json = jsonDecode(
        RegExp(
          r'\{"screenshots".*?\]\}',
          dotAll: true,
        ).firstMatch(rig.client.analyzeCalls.first.utf8Text)!.group(0)!,
      ) as Map<String, dynamic>;
      for (final item in json['screenshots'] as List) {
        expect((item as Map).keys.toSet(), {
          'localAssetId',
          'takenAt',
          'ocrText',
        });
      }
    });
  });

  group('이미지를 붙이는 조건', () {
    test('동의 켜짐 + 글자 수 < 기준값일 때만 붙고, 기준값 이상이면 붙지 않는다', () async {
      rig = await build(
        {'short1': 'a.jpg', 'long1': 'b.jpg'},
        {'short1': _shortText, 'long1': _longText},
      );
      await rig.sync.run();

      final multipart = rig.client.analyzeCalls.single;
      expect(multipart.isMultipart, isTrue);
      expect(multipart.text, contains('name="image.short1"'));
      expect(multipart.text, isNot(contains('name="image.long1"')));
      expect(multipart.text, contains('name="request"'));
    });

    test('동의가 꺼져 있으면 글자가 적어도 이미지를 보내지 않는다', () async {
      rig = await build(
        {'short1': 'a.jpg'},
        {'short1': _shortText},
        consent: false,
      );
      await rig.sync.run();

      expect(rig.client.analyzeCalls.single.isMultipart, isFalse);
      expect(rig.shrinker.calls, isEmpty);
    });

    test('동의를 아직 안 했어도(null) 이미지를 보내지 않는다', () async {
      rig = await build(
        {'short1': 'a.jpg'},
        {'short1': _shortText},
        consent: null,
      );
      await rig.sync.run();

      expect(rig.client.analyzeCalls.single.isMultipart, isFalse);
    });

    test('글자가 없고 이미지도 못 보내면 서버에 보내지 않고 기기에서 ETC로 정한다', () async {
      rig = await build({'blank1': 'a.jpg'}, {}, consent: false);
      await rig.sync.run();

      expect(rig.client.analyzeCalls, isEmpty);
      final v = await rig.capture.verdicts.find('blank1');
      expect(v?.route, LocalRoute.deviceOnly);
      expect(v?.category, Category.etc);
      expect(v?.hidden, isFalse);
    });
  });

  group('보내는 이미지 바이트', () {
    test('EXIF·GPS·XMP·주석이 없다', () async {
      rig = await build({'short1': 'a.jpg'}, {'short1': _shortText});
      await rig.sync.run();

      final call = rig.client.analyzeCalls.single;
      final text = call.text;
      for (final leaked in [
        'Exif',
        'GPSLatitude',
        'GPSLongitude',
        'SAMSUNG',
        'xmpmeta',
        'secret comment',
      ]) {
        expect(text, isNot(contains(leaked)), reason: leaked);
      }
      // 이미지 파트의 JPEG은 그대로 디코딩 가능한 구조(SOI로 시작)로 남아 있다.
      final start =
          text.indexOf('\r\n\r\n', text.indexOf('name="image.short1"')) + 4;
      expect(call.body.sublist(start, start + 2), [0xFF, 0xD8]);
    });

    test('jpegHasMetadata는 가짜 EXIF JPEG을 잡아내고, 정리한 결과는 통과시킨다', () {
      final dirty = jpegWithMetadata();
      expect(jpegHasMetadata(dirty), isTrue);
      final clean = stripJpegMetadata(dirty)!;
      expect(jpegHasMetadata(clean), isFalse);
      expect(latin1.decode(clean), isNot(contains('Exif')));
      expect(clean.length, lessThan(dirty.length));
    });

    test('JPEG이 아니면 보내지 않고 텍스트만으로 보낸다', () async {
      rig = await SyncRig.create(
        photos: photosNamed({'short1': 'a.jpg'}),
        texts: {'short1': _shortText},
        shrinker: FakeShrinker(output: Uint8List.fromList([1, 2, 3, 4, 5])),
      );
      await rig.sync.run();

      expect(rig.client.analyzeCalls.single.isMultipart, isFalse);
    });
  });

  group('로그', () {
    test('동기화 중 출력되는 어떤 로그에도 OCR 원문·파일명·이미지가 없다', () async {
      final printed = <String>[];
      await runZoned(
        () async {
          rig = await build(
            {'p1': 'Screenshot_20261021_101012_Instagram.jpg'},
            {'p1': '비밀원문SENTINEL $_phone'},
          );
          rig.client.failWith['p1'] = 'LLM_CALL_FAILED';
          await rig.sync.run();
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(printed.join('\n'), isNot(contains('SENTINEL')));
      expect(printed.join('\n'), isNot(contains('Instagram')));
      expect(printed.join('\n'), isNot(contains('1234')));
    });

    test('실패해도 예외 메시지에 요청 내용이 없다', () {
      expect(
        const ApiException(ApiFailure.rejected, 400).toString(),
        'ApiException(rejected, 400)',
      );
    });
  });

  group('네트워크 오류', () {
    test('서버가 꺼져 있어도 앱이 죽지 않고 안내 상태가 된다', () async {
      rig = await build({'p1': 'a.jpg'}, {'p1': _longText});
      rig.client.throwOnSend = const SocketException('refused');
      await rig.sync.run();

      expect(rig.status.issue, SyncIssue.offline);
      expect(rig.status.running, isFalse);
      expect(rig.status.issueMessage, contains('서버에 연결하지 못했어요'));
    });

    test('서버가 5xx면 server 안내, 다시 실행하면 이어서 보낸다', () async {
      var down = true;
      late final RecordingClient client;
      client = RecordingClient(
        responder: (r) {
          if (r.path == '/api/screenshots/analyze' && down) {
            return jsonResponse({'error': 'x'}, 503);
          }
          return client.defaultFor(r);
        },
      );
      rig = await SyncRig.create(
        photos: photosNamed({'p1': 'a.jpg'}),
        texts: {'p1': _longText},
        client: client,
      );
      await rig.sync.run();
      expect(rig.status.issue, SyncIssue.server);

      down = false;
      await rig.sync.run();
      expect(rig.status.issue, SyncIssue.none);
      expect((await rig.state.entry('p1'))?.status.name, 'synced');
    });
  });
}
