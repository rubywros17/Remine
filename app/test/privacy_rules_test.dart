import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';
import 'package:remine/data/device/privacy/app_rules.dart';
import 'package:remine/data/device/privacy/phone_masker.dart';
import 'package:remine/data/device/privacy/privacy_filter.dart';
import 'package:remine/data/device/privacy/sensitive_detector.dart';
import 'package:remine/models/category.dart';

Set<String> codes(String text) =>
    detectSensitive(text).map((r) => r.code).toSet();

void main() {
  group('주민등록번호', () {
    test('하이픈·공백 형식 + 유효한 날짜는 잡는다', () {
      expect(codes('주민번호 900101-1234567'), {'SSN'});
      expect(codes('900101 2234567'), {'SSN'});
      expect(codes('외국인 850315-5123456'), {'SSN'});
    });
    test('날짜가 유효하지 않으면 잡지 않는다', () {
      expect(codes('901301-1234567'), isEmpty); // 13월
      expect(codes('900231-1234567'), isEmpty); // 2월 31일
      expect(codes('900101-9234567'), isEmpty); // 성별 자리 9
    });
    test('구분자 없는 13자리는 체크섬이 맞거나 "주민" 문맥이 있을 때만', () {
      expect(codes('9001011234568'), {'SSN'}); // 체크섬 일치
      expect(codes('주민 9001011234567'), {'SSN'}); // 문맥
      expect(codes('주문번호 9001011234567'), isEmpty); // 체크섬 불일치 + 문맥 없음
    });
    test('더 긴 숫자열의 일부는 잡지 않는다', () {
      expect(codes('1900101-12345678'), isEmpty);
    });
  });

  group('카드번호', () {
    test('Luhn을 통과하는 4-4-4-4 형식은 잡는다', () {
      expect(codes('4111 1111 1111 1111'), {'CARD'});
      expect(codes('4111-1111-1111-1111'), {'CARD'});
    });
    test('Luhn에 실패하면 잡지 않는다', () {
      expect(codes('4111 1111 1111 1112'), isEmpty);
    });
    test('구분자 없는 숫자열은 "카드" 문맥 + Luhn일 때만', () {
      expect(codes('카드번호 4111111111111111'), {'CARD'});
      expect(codes('운송장 4111111111111111'), isEmpty); // 문맥 없음
      expect(codes('카드 4111111111111112'), isEmpty); // Luhn 실패
    });
    test('가려진 카드번호는 잡지 않는다', () {
      expect(codes('1234-56**-****-7890'), isEmpty);
    });
  });

  group('계좌번호', () {
    test('하이픈 형식 + 계좌·입금·은행명 문맥은 잡는다', () {
      expect(codes('계좌번호 110-123-456789'), {'ACCOUNT'});
      expect(codes('국민은행 123456-04-123456'), {'ACCOUNT'});
      expect(codes('입금 부탁드려요\n3333-12-3456789'), {'ACCOUNT'});
    });
    test('애매하면 숨긴다: 하이픈 없는 10~14자리도 문맥이 있으면 잡는다', () {
      expect(codes('입금 계좌 12345678901234'), {'ACCOUNT'});
      expect(codes('예금주 홍길동 1002123456789'), {'ACCOUNT'});
    });
    test('문맥이 없으면 잡지 않는다', () {
      expect(codes('110-123-456789'), isEmpty);
      expect(codes('주문번호 1234567890123'), isEmpty);
    });
    test('전화번호 모양은 계좌로 보지 않는다', () {
      expect(codes('은행 문의 010-1234-5678'), isEmpty);
      expect(codes('국민은행 고객센터 1588-9999'), isEmpty);
    });
    test('은행명 문맥은 전체 이름만: "우리 집"·"하나" 같은 흔한 말은 문맥이 아니다', () {
      expect(codes('우리 집 1234567890123'), isEmpty);
      expect(codes('하나 둘 셋 12345678901'), isEmpty);
      expect(codes('기업 소개 110-123-456789'), isEmpty);
      expect(codes('우리은행 1002123456789'), {'ACCOUNT'});
      expect(codes('하나은행 계좌 110-123-456789'), {'ACCOUNT'});
      expect(codes('기업은행 110-123-456789'), {'ACCOUNT'});
    });
    test('날짜·금액은 잡지 않는다', () {
      expect(codes('입금 완료 2024-10-21'), isEmpty);
      expect(codes('입금 1,234,567원'), isEmpty);
    });
  });

  group('인증번호·OTP', () {
    test('인증 문맥 바로 뒤의 4~8자리는 잡는다', () {
      expect(codes('[Web발신] 인증번호 [482913]을 입력해 주세요'), {'OTP'});
      expect(codes('Your verification code is 5821'), {'OTP'});
      expect(codes('OTP: 12345678'), {'OTP'});
    });
    test('숫자가 없는 안내 문구는 잡지 않는다', () {
      expect(codes('인증번호 받기'), isEmpty);
      expect(codes('본인 인증 완료'), isEmpty);
    });
    test('문맥 없는 숫자는 잡지 않는다', () {
      expect(codes('주문 482913 완료'), isEmpty);
    });
    test('너무 짧거나 긴 숫자는 잡지 않는다', () {
      expect(codes('인증번호 123'), isEmpty);
      expect(codes('인증번호 123456789'), isEmpty);
    });
  });

  group('비밀번호', () {
    test('라벨 뒤에 값이 이어지면 잡는다', () {
      expect(codes('비밀번호: abcd1234'), {'PASSWORD'});
      expect(codes('PW=hunter22'), {'PASSWORD'});
      expect(codes('임시 패스워드 : Zx9!kQ'), {'PASSWORD'});
    });
    test('안내·버튼 문구는 잡지 않는다', () {
      expect(codes('비밀번호 변경'), isEmpty);
      expect(codes('비밀번호를 입력하세요'), isEmpty);
      expect(codes('비밀번호: '), isEmpty);
    });
    test('가려진 값은 잡지 않는다', () {
      expect(codes('비밀번호: ●●●●●●'), isEmpty);
      expect(codes('Password: ********'), isEmpty);
    });
  });

  group('전화번호', () {
    test('여러 형식을 [전화번호]로 가린다', () {
      expect(maskPhoneNumbers('문의 010-1234-5678'), '문의 $phoneNumberMask');
      expect(maskPhoneNumbers('01012345678'), phoneNumberMask);
      expect(maskPhoneNumbers('02-123-4567 / 031-1234-5678'),
          '$phoneNumberMask / $phoneNumberMask');
      expect(maskPhoneNumbers('대표 1588-1234'), '대표 $phoneNumberMask');
      expect(maskPhoneNumbers('+82 10-1234-5678'), phoneNumberMask);
    });
    test('날짜·금액·카드·주문번호는 전화번호로 보지 않는다', () {
      for (final t in [
        '2024-10-21',
        '가격 1,234,000원',
        '4111-1111-1111-1111',
        '주문번호 1234567890123',
        '2024.10.21 14:15',
      ]) {
        expect(hasPhoneNumber(t), isFalse, reason: t);
        expect(maskPhoneNumbers(t), t);
      }
    });
    test('마스킹 표시는 서버 PrivacyMarkers.PHONE_NUMBER_MASK와 같은 값', () {
      expect(phoneNumberMask, '[전화번호]');
    });
  });

  group('앱 이름 판정', () {
    test('갤럭시 파일명 끝의 앱 이름을 읽는다', () {
      expect(
        appNameFromFileName('Screenshot_20241021_141546_KakaoTalk.jpg'),
        'KakaoTalk',
      );
      expect(
        appNameFromFileName('Screenshot_20241021_141546_Samsung Internet.jpg'),
        'Samsung Internet',
      );
      expect(
        appNameFromFileName('Screenshot_20241021-141546_토스.png'),
        '토스',
      );
    });
    test('앱 이름이 없는 파일명은 null', () {
      expect(appNameFromFileName('Screenshot_20241021-141546.png'), isNull);
      expect(appNameFromFileName('IMG_0001.jpg'), isNull);
    });
    test('한글·영문 이름 모두 같은 종류로 본다', () {
      expect(appKindOf('KakaoTalk'), AppKind.messenger);
      expect(appKindOf('카카오톡'), AppKind.messenger);
      expect(appKindOf('KakaoBank'), AppKind.financial);
      expect(appKindOf('카카오뱅크'), AppKind.financial);
      expect(appKindOf('토스증권'), AppKind.financial);
      expect(appKindOf('KB Star Banking'), AppKind.financial);
    });
    test('대소문자·공백·기호 차이는 같은 이름으로 본다', () {
      expect(appKindOf('kakaotalk'), AppKind.messenger);
      expect(appKindOf('Shinhan SOL'), AppKind.financial);
      expect(appKindOf('m.Stock'), appKindOf('mStock'));
    });
    test('실기기 이름: 끝의 (숫자)·()는 떼고 비교한다', () {
      expect(appKindOf('Messages(1)'), AppKind.messenger);
      expect(appKindOf('Messages(12)'), AppKind.messenger);
      expect(appKindOf('One UI Home(1)'), isNull); // 목록에 없는 앱은 그대로 없음
      expect(appKindOf('NOL()'), isNull);
      expect(
        appNameFromFileName('Screenshot_20241021_141546_Messages(1).jpg'),
        'Messages(1)',
      );
    });
    test('추가한 앱: KB·Alipay는 금융, WeChat은 메신저, 통화 앱은 숨김', () {
      expect(appKindOf('KB'), AppKind.financial);
      expect(appKindOf('Alipay'), AppKind.financial);
      expect(appKindOf('WeChat'), AppKind.messenger);
      for (final n in ['Phone', 'Call', 'Call settings', 'Call settings(1)']) {
        final v = judgeByApp('Screenshot_20241021_141546_$n.jpg')!;
        expect(v.category, Category.etc, reason: n);
        expect(v.hidden, isTrue, reason: n);
        expect(v.reasons, [ReasonCode.appPrivate], reason: n);
      }
      expect(appKindOf('Phone Book'), isNull); // 부분 일치 아님
    });
    test('부분 일치는 하지 않는다', () {
      expect(appKindOf('KakaoMap'), isNull);
      expect(appKindOf('카카오맵'), isNull);
      expect(appKindOf('Chrome'), isNull);
      expect(appKindOf(null), isNull);
    });
    test('judgeByApp: 메신저는 CHAT 노출, 금융은 ETC 숨김, 둘 다 기기에서 끝', () {
      final chat = judgeByApp('Screenshot_20241021_141546_KakaoTalk.jpg')!;
      expect(chat.route, LocalRoute.deviceOnly);
      expect(chat.category, Category.chat);
      expect(chat.hidden, isFalse);
      expect(chat.reasons, [ReasonCode.appMessenger]);

      final bank = judgeByApp('Screenshot_20241021_141546_KakaoBank.jpg')!;
      expect(bank.route, LocalRoute.deviceOnly);
      expect(bank.category, Category.etc);
      expect(bank.hidden, isTrue);
      expect(bank.reasons, [ReasonCode.appFinancial]);

      expect(judgeByApp('Screenshot_20241021_141546_Chrome.jpg'), isNull);
    });
    test('countByApp: 많은 순으로 앱 이름·장수·종류만 센다', () {
      GalleryPhoto p(String n) => GalleryPhoto(
        id: n,
        fileName: n,
        takenAt: DateTime(2026),
        modifiedAt: 1,
      );
      final counts = countByApp([
        p('Screenshot_20241021_141546_Chrome.jpg'),
        p('Screenshot_20241021_141547_KakaoTalk.jpg'),
        p('Screenshot_20241021_141548_KakaoTalk.jpg'),
        p('Screenshot_20241021-141549.png'),
      ]);
      expect(counts.first.name, 'KakaoTalk');
      expect(counts.first.count, 2);
      expect(counts.first.kind, AppKind.messenger);
      expect(counts.firstWhere((c) => c.name == 'Chrome').kind, isNull);
      expect(counts.any((c) => c.name == null && c.count == 1), isTrue);
    });
  });

  group('judgeByText', () {
    test('강한 민감 정보가 전화번호보다 우선한다', () {
      final v = judgeByText('인증번호 482913 문의 010-1234-5678');
      expect(v.route, LocalRoute.deviceOnly);
      expect(v.category, Category.etc);
      expect(v.hidden, isTrue);
      expect(v.reasons, ['OTP']);
      expect(v.maskedText, isNull);
    });
    test('전화번호만 있으면 가린 텍스트만 보낸다', () {
      final v = judgeByText('맛집 예약 010-1234-5678');
      expect(v.route, LocalRoute.textOnly);
      expect(v.hidden, isFalse);
      expect(v.maskedText, '맛집 예약 $phoneNumberMask');
      expect(v.reasons, [ReasonCode.phone]);
    });
    test('평범한 텍스트는 일반 경로', () {
      final v = judgeByText('니트 가디건 39,000원 무료배송');
      expect(v.route, LocalRoute.normal);
      expect(v.category, isNull);
    });
    test('파일명 판정이 있으면 텍스트는 보지 않는다', () {
      final v = judge(
        'Screenshot_20241021_141546_KakaoTalk.jpg',
        '비밀번호: abcd1234',
      );
      expect(v.reasons, [ReasonCode.appMessenger]);
    });
  });
}
