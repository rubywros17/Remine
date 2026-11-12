import '../models/category.dart';
import '../models/category_summary.dart';
import '../models/category_update.dart';
import '../models/interest.dart';
import '../models/screenshot_item.dart';

/// 화면이 데이터를 가져오는 유일한 경계.
///
/// 지금은 [FakeScreenshotRepository]만 있고, 3주차에 서버 API 구현으로 바꿔 끼운다(화면 코드는 그대로).
/// 메서드는 서버 API와 1:1로 대응한다. (자바의 interface + 구현체 주입과 같은 구조)
///
/// [Dart 메모] `abstract interface class`는 "구현만 할 수 있는" 인터페이스다. `Future<T>`는 비동기 결과
/// (자바의 CompletableFuture), `async/await`로 기다린다.
abstract interface class ScreenshotRepository {
  /// GET /api/screenshots?category=&tag=&page=&size= — 최신순, 분석된 캡처만.
  Future<ScreenshotPage> list({
    Category? category,
    String? tag,
    int page = 0,
    int size = 30,
  });

  /// 휴지통에 없는 캡처 전부(최신순). 정리 탭의 묶음 계산용으로 **기기 안에서만** 쓴다.
  Future<List<ScreenshotItem>> all();

  /// GET /api/categories/summary — 7개 카테고리 전부.
  Future<CategorySummary> summary();

  /// PATCH /api/screenshots/{id}/category — 같은 값이어도 categorySource가 USER가 된다.
  Future<CategoryUpdate> updateCategory(int id, Category category);

  /// 캡처를 앱 휴지통으로 옮긴다. 목록·요약·관심사에서 빠진다.
  /// **앱 안의 개념일 뿐**이다 — 실제 기기 사진 삭제·시스템 휴지통 이동·서버 삭제 API는 3주차 이후(spec F-06).
  Future<void> trash(int id);

  /// 휴지통에서 되돌린다(원래 정렬 위치로 돌아온다).
  Future<void> restore(int id);

  /// 잊은 관심사 목록. (서버 GET /api/interests 형식이 정해지기 전의 임시 계약)
  Future<List<Interest>> interests();
}
