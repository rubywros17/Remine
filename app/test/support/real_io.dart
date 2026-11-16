import 'package:flutter_test/flutter_test.dart';

/// [done]이 참이 될 때까지 실제 시간으로 IO를 흘려보낸다.
///
/// testWidgets는 가짜 시계라 파일 IO(OCR 임시 파일 등)가 진행되지 않는다.
/// IO는 실제 시간(runAsync)에, 그 뒤의 이어받기(await 다음 줄)는 가짜 시계(pump)에서 돌아가므로 번갈아 진행한다.
/// 고정 횟수로 기다리면 전체 테스트처럼 PC가 바쁠 때 IO가 덜 끝나 가끔 실패해서, 조건으로 기다린다.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > timeout) fail('$timeout 안에 조건이 만족되지 않았다');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// "안 일어난다"를 확인하기 전, 일어났다면 충분히 끝났을 만큼 실제 시간으로 흘려보낸다.
/// (기준: 부하 중 전송이 생기기까지 약 1.2초)
Future<void> pumpRealTime(
  WidgetTester tester, [
  Duration duration = const Duration(seconds: 2),
]) {
  final watch = Stopwatch()..start();
  return pumpUntil(
    tester,
    () => watch.elapsed >= duration,
    timeout: duration * 2,
  );
}
