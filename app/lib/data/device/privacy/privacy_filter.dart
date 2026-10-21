import '../../../models/category.dart';
import 'app_rules.dart';
import 'phone_masker.dart';
import 'sensitive_detector.dart';

/// 서버로 어떻게 보낼지(서버 전송은 다음 브랜치 — 여기서는 판정만 한다).
enum LocalRoute {
  /// 기기에서 분류를 끝낸다. 텍스트·이미지 모두 보내지 않는다.
  deviceOnly,

  /// 전화번호를 가린 텍스트만 보낸다. 이미지는 보내지 않는다.
  textOnly,

  /// 일반 경로. 이미지는 동의했고 글자 수가 기준값 미만일 때만.
  normal,
}

/// 판정 사유 코드. 앱 기준 + [SensitiveReason.code] + 전화번호. 이 문자열만 DB에 저장한다.
abstract final class ReasonCode {
  static const appMessenger = 'APP_MESSENGER';
  static const appFinancial = 'APP_FINANCIAL';
  static const phone = 'PHONE';
}

class LocalVerdict {
  const LocalVerdict({
    required this.route,
    this.category,
    this.hidden = false,
    this.reasons = const [],
    this.maskedText,
  });

  final LocalRoute route;

  /// [LocalRoute.deviceOnly]일 때만 값이 있다.
  final Category? category;

  /// 정리 화면에서 기본 숨김. "분석 제외" 필터에서만 보인다.
  final bool hidden;
  final List<String> reasons;

  /// [LocalRoute.textOnly]일 때 전화번호를 가린 텍스트(DB에 넣는 것은 이 값뿐이다).
  final String? maskedText;

  static const normal = LocalVerdict(route: LocalRoute.normal);
}

/// OCR **전**에 파일명의 앱 이름만으로 판단한다. 판정이 나면 OCR도 건너뛴다.
/// 메신저 → CHAT(노출), 은행·증권·카드 → ETC(숨김). 둘 다 서버로 보내지 않는다.
LocalVerdict? judgeByApp(String fileName) {
  final kind = appKindOf(appNameFromFileName(fileName));
  return switch (kind) {
    AppKind.messenger => const LocalVerdict(
      route: LocalRoute.deviceOnly,
      category: Category.chat,
      reasons: [ReasonCode.appMessenger],
    ),
    AppKind.financial => const LocalVerdict(
      route: LocalRoute.deviceOnly,
      category: Category.etc,
      hidden: true,
      reasons: [ReasonCode.appFinancial],
    ),
    null => null,
  };
}

/// OCR 텍스트로 판단한다. 강한 민감 정보가 우선이고, 없으면 전화번호를 가린다.
LocalVerdict judgeByText(String text) {
  final sensitive = detectSensitive(text);
  if (sensitive.isNotEmpty) {
    return LocalVerdict(
      route: LocalRoute.deviceOnly,
      category: Category.etc,
      hidden: true,
      reasons: [for (final r in sensitive) r.code],
    );
  }
  if (hasPhoneNumber(text)) {
    return LocalVerdict(
      route: LocalRoute.textOnly,
      reasons: const [ReasonCode.phone],
      maskedText: maskPhoneNumbers(text),
    );
  }
  return LocalVerdict.normal;
}

/// 파일명 → 텍스트 순서의 전체 판정. 파일명으로 정해지면 [text]는 보지 않는다.
LocalVerdict judge(String fileName, String text) =>
    judgeByApp(fileName) ?? judgeByText(text);
