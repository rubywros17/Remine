import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/device_capture_service.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/ocr_migration.dart';
import 'package:remine/data/device/ocr_store.dart';
import 'package:remine/data/device/ocr_temp_files.dart';
import 'package:remine/data/device/privacy/local_verdict_store.dart';
import 'package:remine/data/device/privacy/phone_masker.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/fake_screenshot_repository.dart';
import 'package:remine/data/local_merged_repository.dart';
import 'package:remine/models/category.dart';

import 'support/fake_device.dart';

// 테스트용 가짜 값. 이 값들이 로그·DB 어디에도 없어야 한다.
const _card = '4111 1111 1111 1111';
const _phone = '010-7777-8888';
const _ssn = '900101-1234567';
const _secrets = [_card, _phone, _ssn, '4111111111111111', '01077778888'];

GalleryPhoto _photo(String id, String fileName, {int modified = 1000}) =>
    GalleryPhoto(
      id: id,
      fileName: fileName,
      takenAt: DateTime(2026, 10, 19, 12).subtract(Duration(minutes: modified)),
      modifiedAt: modified,
    );

void main() {
  late Directory tmp;
  late FakeOcrEngine ocr;
  late InMemoryOcrStore store;
  late InMemoryLocalVerdictStore verdicts;
  late Map<String, String> texts; // photoId -> OCR 텍스트

  DeviceCaptureService service() => DeviceCaptureService(
    reader: FakeGalleryReader(),
    ocr: ocr,
    store: store,
    verdicts: verdicts,
    temp: OcrTempFiles(tmp),
    now: () => DateTime(2026, 10, 21, 12),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('remine_privacy_');
    texts = {};
    store = InMemoryOcrStore();
    verdicts = InMemoryLocalVerdictStore();
    // FakeGalleryReader.bytes()는 id를 그대로 인코딩하므로, 파일 내용 → 텍스트로 되돌려 쓴다.
    ocr = FakeOcrEngine();
    ocr = _ByIdOcr(texts);
  });
  tearDown(() => tmp.delete(recursive: true));

  group('DeviceCaptureService 판정', () {
    test('메신저 앱 파일명은 OCR 없이 CHAT(노출)으로 기기에서 끝난다', () async {
      final run = await service().run([
        _photo('m1', 'Screenshot_20261019_120000_KakaoTalk.jpg'),
      ]);
      expect((ocr as _ByIdOcr).calls, 0);
      expect(run.byApp, 1);
      expect(await store.count(), 0); // OCR 결과도 없다 → 태그·관심사 집계 재료가 없다
      final v = (await verdicts.find('m1'))!;
      expect(v.route, LocalRoute.deviceOnly);
      expect(v.category, Category.chat);
      expect(v.hidden, isFalse);
      expect(v.reasons, [ReasonCode.appMessenger]);
    });

    test('금융 앱 파일명은 OCR 없이 ETC + 숨김', () async {
      await service().run([
        _photo('b1', 'Screenshot_20261019_120000_KakaoBank.jpg'),
      ]);
      expect((ocr as _ByIdOcr).calls, 0);
      final v = (await verdicts.find('b1'))!;
      expect(v.category, Category.etc);
      expect(v.hidden, isTrue);
    });

    test('강한 민감 정보는 본문을 저장하지 않고 ETC + 숨김', () async {
      texts['s1'] = '카드번호 $_card 유효기간 12/28';
      final run = await service().run([_photo('s1', 'Screenshot_1.png')]);
      expect(run.records.single.text, isEmpty);
      expect((await store.find('s1'))!.text, isEmpty);
      expect((await store.find('s1'))!.charCount, greaterThan(0)); // 글자 수만 남는다
      final v = (await verdicts.find('s1'))!;
      expect(v.route, LocalRoute.deviceOnly);
      expect(v.category, Category.etc);
      expect(v.hidden, isTrue);
      expect(v.reasons, ['CARD']);
    });

    test('전화번호는 마스킹본만 저장하고 텍스트만 보낼 대상으로 표시', () async {
      texts['p1'] = '맛집 예약 문의 $_phone 영업시간 11-21시';
      final run = await service().run([_photo('p1', 'Screenshot_2.png')]);
      expect(run.records.single.text, contains(phoneNumberMask));
      expect(run.records.single.text, isNot(contains('7777')));
      final v = (await verdicts.find('p1'))!;
      expect(v.route, LocalRoute.textOnly);
      expect(v.category, isNull);
      expect(v.reasons, [ReasonCode.phone]);
    });

    test('평범한 캡처는 원문을 그대로 저장하고 일반 경로', () async {
      texts['n1'] = '니트 가디건 39,000원';
      await service().run([_photo('n1', 'Screenshot_3.png')]);
      expect((await store.find('n1'))!.text, '니트 가디건 39,000원');
      expect((await verdicts.find('n1'))!.route, LocalRoute.normal);
    });

    test('같은 사진을 다시 돌리면 OCR 없이 건너뛴다(기기 판정 포함)', () async {
      texts['s1'] = '주민번호 $_ssn';
      texts['n1'] = '일반 글자';
      final photos = [
        _photo('s1', 'Screenshot_1.png'),
        _photo('n1', 'Screenshot_3.png'),
        _photo('m1', 'Screenshot_20261019_120000_KakaoTalk.jpg'),
      ];
      await service().run(photos);
      final first = (ocr as _ByIdOcr).calls;
      final again = await service().run(photos);
      expect((ocr as _ByIdOcr).calls, first);
      expect(again.skipped, greaterThanOrEqualTo(2));
    });

    test('사진이 바뀌어 앱 판정이 나면 예전 OCR 본문을 지운다', () async {
      texts['x1'] = '예전에 읽은 글자';
      await service().run([_photo('x1', 'Screenshot_1.png', modified: 1000)]);
      expect(await store.find('x1'), isNotNull);

      await service().run([
        _photo('x1', 'Screenshot_20261019_120000_KakaoBank.jpg', modified: 2000),
      ]);
      expect(await store.find('x1'), isNull);
      expect((await verdicts.find('x1'))!.hidden, isTrue);
    });
  });

  group('원문·감지 값이 남지 않는다', () {
    test('실행 중 출력(print/debugPrint)과 저장된 모든 값에 없다', () async {
      texts['s1'] = '카드 $_card';
      texts['s2'] = '주민등록번호 $_ssn';
      texts['p1'] = '문의 $_phone';
      texts['a1'] = '계좌번호 110-123-456789 비밀번호: hunter22 인증번호 482913';
      final printed = <String>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (msg, {wrapWidth}) => printed.add(msg ?? '');
      late OcrRun run;
      await runZoned(
        () async => run = await service().run([
          _photo('s1', 'Screenshot_1.png', modified: 1),
          _photo('s2', 'Screenshot_2.png', modified: 2),
          _photo('p1', 'Screenshot_3.png', modified: 3),
          _photo('a1', 'Screenshot_4.png', modified: 4),
          _photo('m1', 'Screenshot_20261019_120000_KakaoTalk.jpg', modified: 5),
        ]),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      debugPrint = oldDebugPrint;

      // 저장 내용 전체를 한 문자열로 모은다: OCR 행 + 판정 행(DB에 들어가는 값 그대로).
      final dump = StringBuffer(printed.join('\n'));
      for (final r in run.records) {
        dump
          ..write(r.text)
          ..write(r.fileName);
      }
      for (final v in verdicts.all) {
        dump.write(storedVerdictToRow(v));
      }
      for (final id in ['s1', 's2', 'p1', 'a1', 'm1']) {
        final r = await store.find(id);
        if (r != null) dump.write(r.text);
      }
      final all = dump.toString();
      for (final secret in [..._secrets, 'hunter22', '482913', '456789']) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
    });

    test('판정 저장 행은 정해진 컬럼뿐이고 사유는 코드 문자열이다', () {
      final row = storedVerdictToRow(
        StoredVerdict.of(
          judgeByText('카드 $_card'),
          assetId: 'a',
          takenAt: DateTime(2026),
          modifiedAt: 1,
          now: DateTime(2026),
        ),
      );
      expect(row.keys.toSet(), {
        'asset_id', 'taken_at', 'modified_at', 'route', 'category', //
        'hidden', 'reasons', 'decided_at',
      });
      expect(row['reasons'], 'CARD');
    });
  });

  group('DB v1 → v2 마이그레이션(기존 행 재필터)', () {
    OcrRecord old(String id, String file, String text) => OcrRecord(
      assetId: id,
      fileName: file,
      modifiedAt: 1000,
      text: text,
      charCount: OcrRecord.countChars(text),
      ocrAt: DateTime(2026, 10, 1),
      engine: 'mlkit-korean',
    );
    final now = DateTime(2026, 10, 21);

    test('민감 캡처는 본문을 비우고 숨김 판정을 만든다', () {
      final r = refilterOcrRecord(
        old('s', 'Screenshot_1.png', '카드번호 $_card'),
        now: now,
      );
      expect(r.record.text, isEmpty);
      expect(r.record.charCount, greaterThan(0));
      expect(r.verdict.hidden, isTrue);
      expect(r.verdict.reasons, ['CARD']);
      expect(r.verdict.category, Category.etc);
    });

    test('전화번호 캡처는 마스킹본으로 바꾼다', () {
      final r = refilterOcrRecord(
        old('p', 'Screenshot_2.png', '예약 $_phone 환영'),
        now: now,
      );
      expect(r.record.text, '예약 $phoneNumberMask 환영');
      expect(r.verdict.route, LocalRoute.textOnly);
    });

    test('메신저·금융 앱 파일명이면 본문을 비운다', () {
      final chat = refilterOcrRecord(
        old('m', 'Screenshot_20261019_120000_KakaoTalk.jpg', '안녕 내일 봐'),
        now: now,
      );
      expect(chat.record.text, isEmpty);
      expect(chat.verdict.category, Category.chat);
      expect(chat.verdict.hidden, isFalse);
      final bank = refilterOcrRecord(
        old('b', 'Screenshot_20261019_120000_Toss.jpg', '잔액'),
        now: now,
      );
      expect(bank.record.text, isEmpty);
      expect(bank.verdict.hidden, isTrue);
    });

    test('평범한 행은 그대로 두고 일반 판정만 만든다', () {
      final src = old('n', 'Screenshot_3.png', '니트 가디건');
      final r = refilterOcrRecord(src, now: now);
      expect(r.record.text, src.text);
      expect(r.verdict.route, LocalRoute.normal);
    });

    test('결과에 원문이 남지 않고, 다시 돌려도 같은 결과다', () {
      final first = refilterOcrRecord(
        old('s', 'Screenshot_1.png', '주민번호 $_ssn 문의 $_phone'),
        now: now,
      );
      final second = refilterOcrRecord(first.record, now: now);
      expect(second.record.text, first.record.text);
      for (final s in _secrets) {
        expect(first.record.text, isNot(contains(s)));
        expect(storedVerdictToRow(first.verdict).toString(), isNot(contains(s)));
      }
    });
  });

  group('홈 합산(LocalMergedRepository)', () {
    final now = DateTime(2026, 10, 19, 12);
    late FakeScreenshotRepository base;
    late LocalMergedRepository merged;

    Future<void> put(String id, LocalVerdict v, int minutesAgo) =>
        verdicts.save(
          StoredVerdict.of(
            v,
            assetId: id,
            takenAt: now.add(Duration(days: 1, minutes: -minutesAgo)), // 가짜 데이터보다 항상 최신
            modifiedAt: 1,
            now: now,
          ),
        );

    setUp(() async {
      base = FakeScreenshotRepository(now: () => now);
      merged = LocalMergedRepository(base, verdicts);
      await put(
        'chat1',
        judgeByApp('Screenshot_20261019_120000_KakaoTalk.jpg')!,
        1,
      );
      await put(
        'bank1',
        judgeByApp('Screenshot_20261019_120000_KakaoBank.jpg')!,
        2,
      );
      await put('card1', judgeByText('카드 $_card'), 3);
      await put('plain', LocalVerdict.normal, 4);
    });

    test('개수는 숨김이 아닌 기기 분류만 더한다(CHAT +1, ETC 변화 없음)', () async {
      final b = await base.summary();
      final m = await merged.summary();
      expect(m.of(Category.chat).count, b.of(Category.chat).count + 1);
      expect(m.of(Category.etc).count, b.of(Category.etc).count);
      expect(m.total, b.total + 1);
      expect(m.of(Category.chat).recentAssetIds.first, 'chat1'); // 가장 최신
    });

    test('목록에는 CHAT 항목이 음수 id로 들어오고 숨김 항목은 없다', () async {
      final chat = await merged.list(category: Category.chat);
      expect(chat.items.first.localAssetId, 'chat1');
      expect(chat.items.first.id, lessThan(0));
      final etc = await merged.list(category: Category.etc, size: 100);
      expect(
        etc.items.map((s) => s.localAssetId),
        isNot(anyOf(contains('bank1'), contains('card1'))),
      );
      expect(
        chat.totalElements,
        (await base.list(category: Category.chat)).totalElements + 1,
      );
    });

    test('태그로 거르면 기기 분류 캡처는 빠진다', () async {
      final r = await merged.list(category: Category.chat, tag: '없는태그');
      expect(r.items, isEmpty);
    });

    test('숨김 항목은 deviceOnly(hidden: true)로만 모인다', () async {
      final hidden = await verdicts.deviceOnly(hidden: true);
      expect(hidden.map((v) => v.assetId), ['bank1', 'card1']);
    });

    test('기기 분류 캡처의 카테고리 수정은 아직 지원하지 않는다', () async {
      final id = (await merged.list(category: Category.chat)).items.first.id;
      expect(() => merged.updateCategory(id, Category.info), throwsStateError);
    });
  });
}

/// 사진 id로 정해 둔 텍스트를 돌려주는 OCR(FakeGalleryReader.bytes는 id를 그대로 인코딩한다).
class _ByIdOcr extends FakeOcrEngine {
  _ByIdOcr(this.texts);

  final Map<String, String> texts;
  int calls = 0;

  @override
  Future<String> recognize(File image) async {
    calls++;
    final id = String.fromCharCodes(await image.readAsBytes());
    return texts[id] ?? '글자';
  }
}
