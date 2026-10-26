import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Firebase 설정·서버 키 같은 비밀 파일이 커밋되지 않는다. 저장소 전체(app·server)를 git으로 본다.
void main() {
  ProcessResult git(List<String> args) =>
      Process.runSync('git', ['-C', '..', ...args]);

  final secret = RegExp(
    r'(^|/)(google-services\.json|GoogleService-Info\.plist|[^/]*firebase-admin[^/]*\.json'
    r'|[^/]*serviceAccount[^/]*\.json|[^/]*\.env|\.env\.[^/]+)$',
  );

  test('비밀 파일이 git에 올라가 있지 않다', () {
    final r = git(['ls-files']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final tracked = (r.stdout as String)
        .split('\n')
        .where((f) => secret.hasMatch(f) && !f.endsWith('.env.example'))
        .toList();
    expect(tracked, isEmpty);
  });

  test('google-services.json·서버 키 파일은 .gitignore가 막는다', () {
    for (final path in [
      'app/android/app/google-services.json',
      'server/firebase-adminsdk-abc.json',
      'server/firebase-admin.json',
      'remine.env',
      'server/remine-serviceAccount.json',
      '.env',
    ]) {
      // --no-index: 파일이 없어도(또는 이미 추적 중이어도) 규칙만으로 판정한다.
      final r = git(['check-ignore', '-q', '--no-index', path]);
      expect(r.exitCode, 0, reason: '$path 가 무시되지 않는다');
    }
  });
}
