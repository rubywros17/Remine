import 'dart:typed_data';

/// 사진 접근 권한 상태. Android 14의 "일부만 허용"이 [limited]다.
enum GalleryAccess { authorized, limited, denied }

class GalleryAlbum {
  const GalleryAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.relativePath,
    this.isScreenshots = false,
  });

  final String id;
  final String name;
  final int count;

  /// 저장 위치(예: `DCIM/Screenshots/`). 이름이 같은 앨범을 가를 때 쓴다. 알 수 없으면 null.
  final String? relativePath;

  /// 기본 소스로 고른 Screenshots 앨범인지. [orderAlbums]가 한 앨범에만 표시한다.
  final bool isScreenshots;
}

const _screenshotNames = {'screenshots', 'screenshot', '스크린샷'};

bool _isDcimScreenshots(GalleryAlbum a) =>
    (a.relativePath ?? '').toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
    'dcim/screenshots';

/// 앨범을 정렬하고 **기본 소스 하나**에만 [GalleryAlbum.isScreenshots]를 표시해 맨 앞에 둔다.
///
/// 기본 소스: ① 이름이 Screenshots/스크린샷이고 경로가 `DCIM/Screenshots`인 앨범
/// ② 없으면 이름만 맞는 앨범 중 사진이 가장 많은 것. 같은 이름의 다른 앨범은 자동으로 합치지 않고,
/// 측정 화면 칩에서 직접 고를 때만 쓴다. 나머지는 이름순.
List<GalleryAlbum> orderAlbums(List<GalleryAlbum> albums) {
  bool named(GalleryAlbum a) => _screenshotNames.contains(a.name.toLowerCase());
  GalleryAlbum? pickMostPhotos(Iterable<GalleryAlbum> xs) =>
      xs.isEmpty ? null : xs.reduce((a, b) => b.count > a.count ? b : a);

  final named_ = albums.where(named).toList();
  final chosen =
      pickMostPhotos(named_.where(_isDcimScreenshots)) ??
      pickMostPhotos(named_);

  GalleryAlbum flag(GalleryAlbum a) => GalleryAlbum(
    id: a.id,
    name: a.name,
    count: a.count,
    relativePath: a.relativePath,
    isScreenshots: a.id == chosen?.id,
  );
  final result = albums.map(flag).toList()
    ..sort((a, b) {
      if (a.isScreenshots != b.isScreenshots) return a.isScreenshots ? -1 : 1;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  return result;
}

class GalleryPhoto {
  const GalleryPhoto({
    required this.id,
    required this.fileName,
    required this.takenAt,
    required this.modifiedAt,
  });

  final String id;
  final String fileName;
  final DateTime takenAt;

  /// 사진이 바뀌었는지 보는 값(epoch 초). OCR 캐시 키의 일부.
  final int modifiedAt;
}

final _fileNameDate = RegExp(r'(\d{4})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})');

/// 갤럭시 스크린샷 파일명(`Screenshot_20261008_170925_Instagram.jpg`)에서 찍은 시각을 읽는다. 없거나 날짜가 말이 안 되면 null.
DateTime? takenAtFromFileName(String fileName) {
  final m = _fileNameDate.firstMatch(fileName);
  if (m == null) return null;
  final n = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  final t = DateTime(n[0], n[1], n[2], n[3], n[4], n[5]);
  // DateTime은 13월 같은 값을 다음 해로 넘겨 버리므로, 읽은 값 그대로인지 확인한다.
  final same =
      t.year == n[0] && t.month == n[1] && t.day == n[2] && t.hour == n[3];
  return same && n[0] >= 2000 && n[0] <= 2100 ? t : null;
}

/// 목록에 보일 "찍은 시각". 우선순위: 촬영 시각([created]) → 파일명의 날짜 → 수정 시각.
///
/// 단, [created]와 파일명 날짜가 하루 넘게 다르면 **파일명을 믿는다**. 사진을 `adb push`·복사로 옮기면
/// 갤러리가 "찍은 시각"을 옮긴 날로 기록해 전부 같은 날로 보이기 때문이다(갤럭시 스크린샷 파일명은 실제 촬영 시각).
/// [created]가 없거나 1970년(알 수 없음)이면 건너뛴다.
DateTime resolveTakenAt({
  DateTime? created,
  required String fileName,
  required int modifiedAtSeconds,
}) {
  final createdOk = created != null && created.year >= 2000 ? created : null;
  final named = takenAtFromFileName(fileName);
  if (createdOk != null && named != null) {
    return createdOk.difference(named).abs() > const Duration(days: 1)
        ? named
        : createdOk;
  }
  return createdOk ??
      named ??
      DateTime.fromMillisecondsSinceEpoch(modifiedAtSeconds * 1000);
}

/// 기기 갤러리를 읽는 경계. 구현은 photo_manager, 테스트는 Fake로 바꿔 끼운다.
/// 이미지는 기기 밖으로 나가지 않는다 — 여기서 나온 바이트는 기기 안 OCR에만 쓴다.
abstract interface class GalleryReader {
  /// [request]가 true면 권한 팝업을 띄운다.
  Future<GalleryAccess> access({bool request = false});

  /// "일부만 허용"에서 사진을 다시 고르는 시스템 선택창.
  Future<void> reselect();

  Future<void> openSettings();

  /// 이미지 앨범 목록. Screenshots 앨범이 있으면 맨 앞.
  Future<List<GalleryAlbum>> albums();

  /// 최신순 최대 [limit]장.
  Future<List<GalleryPhoto>> recent(String albumId, {int limit = 300});

  /// 썸네일. [height]를 주면 [size] × [height]로(사진 비율에 맞춰) 요청한다 — 정사각으로 요청하면 가운데만 잘려 나온다.
  Future<Uint8List?> thumbnail(String photoId, {int size = 220, int? height});

  /// 사진의 폭/높이 비율(회전 반영). 알 수 없으면 null.
  Future<double?> aspectRatio(String photoId);

  /// OCR 입력용 원본 바이트.
  Future<Uint8List?> bytes(String photoId);
}
