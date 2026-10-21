/// 전화번호 마스킹 표시. 서버 `PrivacyMarkers.PHONE_NUMBER_MASK`와 **같은 값**이어야 한다
/// (서버는 OCR에 이 표시가 있으면 이미지를 쓰지 않는다). 한쪽을 바꾸면 다른 쪽도 바꾼다.
const phoneNumberMask = '[전화번호]';

// 앞뒤에 숫자·하이픈이 더 붙어 있으면 더 긴 번호(카드·주문번호 등)의 일부라서 전화번호로 보지 않는다.
const _b = r'(?<![\d-])';
const _e = r'(?![\d-])';

/// 휴대폰(구분자 생략 가능) · 지역번호(구분자 필수) · 대표번호 1588-1234 · +82.
final phonePattern = RegExp(
  '$_b(?:'
  r'01[016789][-.\s]?\d{3,4}[-.\s]?\d{4}'
  r'|0(?:2|[3-6]\d)[-.\s]\d{3,4}[-.\s]\d{4}'
  r'|1[5-9]\d{2}[-\s]\d{4}'
  '|'
  r'\+82[-\s]?(?:10|[2-6]\d?)[-\s]?\d{3,4}[-\s]?\d{4}'
  ')$_e',
);

bool hasPhoneNumber(String text) => phonePattern.hasMatch(text);

String maskPhoneNumbers(String text) =>
    text.replaceAll(phonePattern, phoneNumberMask);
