import '../gallery_reader.dart';

/// 기기 안에서 앱 이름만으로 분류하는 앱 목록. **앱 이름을 추가·수정할 때는 이 파일만 고친다.**
///
/// 갤럭시 스크린샷 파일명은 `Screenshot_20241021_141546_KakaoTalk.jpg`처럼 끝에 앱 이름이 붙는다.
/// 이름은 정규화한 뒤 **완전 일치**로만 비교한다(부분 일치는 "카카오맵"이 "카카오톡"으로 걸리는 식의 오탐이 난다).
/// 한글·영문 이름을 둘 다 넣는다 — 실기기의 실제 이름은 디버그 측정 화면의 "앱 이름별 개수"로 확인한다.
enum AppKind { messenger, financial, privateApp }

const _messengerApps = [
  'KakaoTalk', '카카오톡',
  'Messages', '메시지',
  'Telegram', '텔레그램',
  'LINE', '라인',
  'WhatsApp',
  'Discord', '디스코드',
  'Slack',
  'Signal',
  'Band', '밴드',
  'WeChat', '위챗',
];

const _financialApps = [
  // 은행
  'KakaoBank', '카카오뱅크',
  'KB Star Banking', 'KB스타뱅킹', 'KB Pay', 'KB페이',
  'Shinhan SOL', '신한 SOL', '신한SOL뱅크', '쏠',
  'NH스마트뱅킹', 'NH Smart Banking', 'NH올원뱅크', 'NH OnePay',
  'Woori WON', '우리WON뱅킹', '우리원뱅킹',
  'Hana 1Q', '하나원큐', 'Hana Bank',
  'IBK ONE뱅크', 'IBK ONE Bank', 'i-ONE Bank',
  'Toss', '토스',
  'K bank', '케이뱅크', 'KBank',
  '토스뱅크', 'Toss Bank',
  'SC제일은행', 'SC Bank',
  'Citi', '씨티은행',
  'Post Bank', '우체국',
  '새마을금고', 'MG새마을금고',
  // 증권
  'Toss Securities', '토스증권',
  'Kiwoom', '영웅문', '키움증권',
  'm.Stock', 'mStock', '미래에셋증권', '엠스톡',
  'NAMUH', '나무', '나무증권',
  'KB M-able', 'KB증권', 'M-able',
  'Samsung Securities', '삼성증권', 'mPOP',
  'Shinhan Investment', '신한투자증권', '신한 SOL증권',
  'Korea Investment', '한국투자', '한국투자증권',
  // 카드·간편결제
  'Samsung Card', '삼성카드',
  'Hyundai Card', '현대카드',
  'Shinhan Pay', '신한플레이', 'Shinhan Play',
  'Lotte Card', '롯데카드',
  'BC Card', '페이북', 'PAYBOOC',
  'Samsung Pay', '삼성페이', 'Samsung Wallet', '삼성 월렛',
  'Naver Pay', '네이버페이',
  'Kakao Pay', '카카오페이',
  'Payco', '페이코',
  'Alipay', '알리페이',
  'KB', // 실기기에서 "KB"로만 찍히는 KB 금융 앱
];

/// 금융은 아니지만 통화 기록·연락처가 보여서 숨기는 앱(금융과 같이 기타 + 숨김).
const _privateApps = [
  'Phone', '전화',
  'Call', '통화',
  'Call settings', '통화 설정',
];

/// 비교용 정규화: 소문자로 바꾸고 글자·숫자가 아닌 문자(공백·`.`·`-`·`_`)를 지운다.
/// 파일명 끝의 "(1)", "()"는 먼저 떼어 낸다(예: `Messages(1)`, `One UI Home(1)`, `NOL()`).
String normalizeAppName(String name) => name
    .replaceAll(RegExp(r'\(\d*\)\s*$'), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^0-9a-z가-힣ㄱ-ㅎ]'), '');

final Map<String, AppKind> _kindByName = {
  for (final n in _messengerApps) normalizeAppName(n): AppKind.messenger,
  for (final n in _financialApps) normalizeAppName(n): AppKind.financial,
  for (final n in _privateApps) normalizeAppName(n): AppKind.privateApp,
};

AppKind? appKindOf(String? appName) =>
    appName == null ? null : _kindByName[normalizeAppName(appName)];

final _appNamePattern = RegExp(
  r'^Screenshot_\d{8}[_-]\d{6}_(.+)\.[A-Za-z0-9]+$',
);

/// 갤럭시 스크린샷 파일명 끝의 앱 이름. 다른 형식(예: 픽셀)이면 null.
String? appNameFromFileName(String fileName) =>
    _appNamePattern.firstMatch(fileName)?.group(1)?.trim();

/// 파일명 앱 이름이 `Remine`인지(대소문자·공백 무관). 파일명만으로 알 수 있는 자기 캡처.
/// 실기기(갤럭시)는 Remine 화면 캡처에 앱 이름을 붙이지 않아서, 나머지는 [OwnCaptureRule]이 촬영 시각으로 잡는다.
/// 우리 앱 화면을 찍은 캡처는 분류할 대상이 아니다 → OCR도 전송도 하지 않고 목록에도 올리지 않는다.
bool isOwnAppCapture(String fileName) =>
    normalizeAppName(appNameFromFileName(fileName) ?? '') == 'remine';

final _namelessPattern = RegExp(r'^Screenshot_\d{8}[_-]\d{6}\.[A-Za-z0-9]+$');

/// 스크린샷 파일명인데 앱 이름이 없음(예: `Screenshot_20261026_151044.jpg`). 갤럭시는 Remine 화면을 이렇게 남긴다.
bool isNamelessScreenshot(String fileName) =>
    _namelessPattern.hasMatch(fileName);

/// 디버그 화면용: 파일명 앱 이름별 장수. 앱 이름이 없는 파일은 [name]이 null.
class AppCount {
  const AppCount(this.name, this.count, this.kind);

  final String? name;
  final int count;

  /// 위 목록에 있으면 종류, 없으면 null(= 아직 모르는 앱).
  final AppKind? kind;
}

List<AppCount> countByApp(Iterable<GalleryPhoto> photos) {
  final counts = <String?, int>{};
  for (final p in photos) {
    final name = appNameFromFileName(p.fileName);
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final list = [
    for (final e in counts.entries) AppCount(e.key, e.value, appKindOf(e.key)),
  ];
  list.sort(
    (a, b) => b.count != a.count
        ? b.count.compareTo(a.count)
        : (a.name ?? '').compareTo(b.name ?? ''),
  );
  return list;
}
