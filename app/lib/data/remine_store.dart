import 'package:flutter/widgets.dart';

import '../models/category.dart';
import '../models/category_update.dart';
import 'screenshot_repository.dart';

/// 앱 전체가 공유하는 상태. 데이터는 [repository]에서 읽고, 카테고리를 바꾸면 [revision]을 올려
/// 홈·카테고리 화면이 다시 불러오게 한다.
///
/// [Flutter 메모] ChangeNotifier는 "값이 바뀌었다"고 구독자에게 알리는 내장 클래스(옵저버 패턴)다.
/// 상태관리 패키지(Provider·Riverpod 등) 없이 이것과 [RemineScope](InheritedNotifier)만으로 충분한 규모라서 썼다.
class RemineStore extends ChangeNotifier {
  RemineStore(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final ScreenshotRepository repository;

  /// 현재 시각(테스트에서 고정하려고 주입).
  final DateTime Function() now;

  int _revision = 0;

  /// 가짜 데이터 모드(기기 설정이 없을 때) 상세 "위로 밀어 삭제" 안내를 봤는지. 앱 실행 동안만 기억한다
  /// (스토어가 앱마다 새로 생겨 테스트끼리 섞이지 않는다). 기기 모드는 SettingsStore에 저장한다.
  bool swipeTutorialSeen = false;

  /// 데이터가 바뀔 때마다 1씩 오른다. 화면은 이 값이 달라지면 다시 불러온다.
  int get revision => _revision;

  /// 휴지통으로 옮긴다. 홈·카테고리의 개수와 목록이 바로 갱신된다.
  Future<void> trash(int id) async {
    await repository.trash(id);
    _revision++;
    notifyListeners();
  }

  /// 휴지통에서 되돌린다.
  Future<void> restore(int id) async {
    await repository.restore(id);
    _revision++;
    notifyListeners();
  }

  /// repository 밖에서 데이터가 바뀌었을 때(기기 안 분류가 끝났을 때 등) 화면이 다시 불러오게 한다.
  void refresh() {
    _revision++;
    notifyListeners();
  }

  Future<CategoryUpdate> changeCategory(int id, Category category) async {
    final result = await repository.updateCategory(id, category);
    _revision++;
    notifyListeners();
    return result;
  }
}

/// 위젯 트리 어디서든 [RemineStore]를 꺼내 쓰게 한다. store가 알리면 이걸 읽은 위젯이 다시 그려진다.
class RemineScope extends InheritedNotifier<RemineStore> {
  const RemineScope({
    super.key,
    required RemineStore store,
    required super.child,
  }) : super(notifier: store);

  static RemineStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemineScope>()?.notifier;

  static RemineStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RemineScope>();
    assert(scope != null, 'RemineScope가 위젯 트리 위쪽에 없어요');
    return scope!.notifier!;
  }
}
