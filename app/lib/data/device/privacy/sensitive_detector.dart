import 'phone_masker.dart';

/// 강한 민감 정보의 사유 코드. 로컬 DB에는 이 코드만 저장한다(감지된 값은 어디에도 남기지 않는다).
enum SensitiveReason {
  ssn('SSN'),
  card('CARD'),
  account('ACCOUNT'),
  otp('OTP'),
  password('PASSWORD');

  const SensitiveReason(this.code);
  final String code;
}

/// OCR 텍스트에서 강한 민감 정보를 찾는다. 형식과 문맥을 함께 본다.
/// 반환값은 사유뿐이고, 어디서 무엇이 걸렸는지는 돌려주지 않는다.
Set<SensitiveReason> detectSensitive(String text) => {
  if (_hasSsn(text)) SensitiveReason.ssn,
  if (_hasCard(text)) SensitiveReason.card,
  if (_hasAccount(text)) SensitiveReason.account,
  if (_hasOtp(text)) SensitiveReason.otp,
  if (_hasPassword(text)) SensitiveReason.password,
};

// ── 주민등록번호 ────────────────────────────────────────────────
// 2020.10 이후 발급분은 체크섬이 맞지 않으므로 체크섬은 "구분자 없는 13자리"의 보조 근거로만 쓴다.
final _ssnPattern = RegExp(
  r'(?<!\d)(\d{2})(\d{2})(\d{2})([- ]?)([1-8])(\d{6})(?!\d)',
);

bool _validDate(int m, int d) {
  if (m < 1 || m > 12 || d < 1) return false;
  const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return d <= days[m - 1];
}

bool _ssnChecksum(String digits13) {
  const w = [2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5];
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(digits13[i]) * w[i];
  }
  return (11 - sum % 11) % 10 == int.parse(digits13[12]);
}

bool _hasSsn(String text) {
  for (final m in _ssnPattern.allMatches(text)) {
    if (!_validDate(int.parse(m[2]!), int.parse(m[3]!))) continue;
    final separated = m[4]!.isNotEmpty;
    final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
    // 구분자 없는 13자리는 흔한 숫자열이라 체크섬이 맞거나 "주민" 문맥이 있을 때만.
    if (separated || _ssnChecksum(digits) || text.contains('주민')) return true;
  }
  return false;
}

// ── 카드번호 ────────────────────────────────────────────────────
final _cardGrouped = RegExp(
  r'(?<!\d)(?:\d{4}([-\s])\d{4}\1\d{4}\1\d{4}|\d{4}([-\s])\d{6}\2\d{5})(?!\d)',
);
final _cardPlain = RegExp(r'(?<!\d)\d{13,19}(?!\d)');
final _cardContext = RegExp(r'카드|card|visa|master', caseSensitive: false);

bool _luhn(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = int.parse(digits[digits.length - 1 - i]);
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}

bool _hasCard(String text) {
  for (final m in _cardGrouped.allMatches(text)) {
    if (_luhn(m[0]!.replaceAll(RegExp(r'\D'), ''))) return true;
  }
  // 구분자 없는 13~19자리는 "카드" 문맥이 있을 때만 본다.
  if (_cardContext.hasMatch(text)) {
    for (final m in _cardPlain.allMatches(text)) {
      if (_luhn(m[0]!)) return true;
    }
  }
  return false;
}

// ── 계좌번호 ────────────────────────────────────────────────────
// 계좌는 체크섬이 없어서 문맥이 필수다. 애매하면 숨기는 쪽으로 판단한다:
// 하이픈 없는 10~14자리도 문맥(계좌·입금·예금주·은행명)이 있으면 계좌로 본다.
final _accountPattern = RegExp(
  r'(?<![\d-])(?:\d{2,6}-\d{2,6}-\d{2,7}(?:-\d{1,4})?|\d{10,14})(?![\d-])',
);
final _accountContext = RegExp(
  r'계좌|입금|출금|예금주|무통장|'
  r'은행|국민|신한|우리|하나|농협|기업|카카오뱅크|토스뱅크|케이뱅크|새마을|우체국|수협|SC제일|씨티|'
  r'bank',
  caseSensitive: false,
);

/// 후보 앞뒤로 이 글자 수 안에 문맥 단어가 있으면 "근처"로 본다.
const _contextWindow = 30;

bool _hasAccount(String text) {
  final phones = phonePattern.allMatches(text).toList();
  for (final m in _accountPattern.allMatches(text)) {
    final digits = m[0]!.replaceAll('-', '').length;
    if (digits < 10 || digits > 14) continue;
    // 전화번호 모양은 계좌로 보지 않는다.
    if (phones.any((p) => p.start < m.end && m.start < p.end)) continue;
    final from = (m.start - _contextWindow).clamp(0, text.length);
    final to = (m.end + _contextWindow).clamp(0, text.length);
    if (_accountContext.hasMatch(text.substring(from, to))) return true;
  }
  return false;
}

// ── 인증번호·OTP ────────────────────────────────────────────────
final _otpPattern = RegExp(
  r'(?:인증\s*번호|인증\s*코드|확인\s*번호|확인\s*코드|보안\s*코드|일회용|OTP|verification\s*code|security\s*code)'
  r'[^\d\n]{0,20}(?<!\d)\d{4,8}(?!\d)',
  caseSensitive: false,
);

bool _hasOtp(String text) => _otpPattern.hasMatch(text);

// ── 비밀번호 ────────────────────────────────────────────────────
// "비밀번호 변경", "비밀번호를 입력하세요" 같은 안내 문구는 라벨 뒤에 `:`/`=`와 값이 이어질 때만 잡는다.
final _passwordPattern = RegExp(
  r'(?:비밀\s*번호|패스워드|passwd|password|\bpw\b|\bpin\b|핀\s*번호)\s*[:=]\s*(\S{4,})',
  caseSensitive: false,
);
final _maskedValue = RegExp(r'^[*●•·○×xX]+$');

bool _hasPassword(String text) => _passwordPattern
    .allMatches(text)
    .any((m) => !_maskedValue.hasMatch(m[1]!));
