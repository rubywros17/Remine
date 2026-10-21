import 'package:flutter_test/flutter_test.dart';
import 'package:remine/data/device/gallery_reader.dart';

GalleryAlbum album(String id, String name, int count, [String? path]) =>
    GalleryAlbum(id: id, name: name, count: count, relativePath: path);

String? defaultId(List<GalleryAlbum> albums) =>
    orderAlbums(albums)
        .where((a) => a.isScreenshots)
        .map((a) => a.id)
        .singleOrNull;

void main() {
  group('Screenshots 기본 소스 고르기', () {
    test('이름이 같은 앨범이 여럿이면 DCIM/Screenshots 경로를 우선한다 (사진이 더 적어도)', () {
      final albums = [
        album('a', 'Screenshots', 500, 'Pictures/Screenshots/'),
        album('b', 'Screenshots', 40, 'DCIM/Screenshots/'),
        album('c', 'Camera', 900, 'DCIM/Camera/'),
      ];

      expect(defaultId(albums), 'b');
      expect(orderAlbums(albums).first.id, 'b');
    });

    test('DCIM/Screenshots가 없으면 이름이 맞는 앨범 중 사진이 가장 많은 것', () {
      final albums = [
        album('a', 'Screenshots', 30, 'Pictures/Screenshots/'),
        album('b', '스크린샷', 120, 'Pictures/스크린샷/'),
        album('c', 'Camera', 900, 'DCIM/Camera/'),
      ];

      expect(defaultId(albums), 'b');
    });

    test('경로를 알 수 없어도(null) 이름으로 대체한다', () {
      expect(
        defaultId([album('a', 'Screenshots', 3), album('b', 'Screenshots', 9)]),
        'b',
      );
    });

    test('기본 소스는 하나뿐이고, 같은 이름의 다른 앨범도 칩에는 남는다 (자동 포함은 안 함)', () {
      final albums = [
        album('a', 'Screenshots', 500, 'Pictures/Screenshots/'),
        album('b', 'Screenshots', 40, 'DCIM/Screenshots/'),
      ];

      final ordered = orderAlbums(albums);

      expect(ordered.where((a) => a.isScreenshots), hasLength(1));
      expect(ordered.map((a) => a.id), containsAll(['a', 'b']));
    });

    test('Screenshots류 앨범이 없으면 기본 소스를 정하지 않는다', () {
      expect(
        defaultId([
          album('c', 'Camera', 10),
          album('d', 'RemineExperiment', 5),
        ]),
        isNull,
      );
    });

    test('경로 대소문자·끝 슬래시 차이는 무시한다', () {
      expect(
        defaultId([
          album('a', 'Screenshots', 500, 'Pictures/Screenshots'),
          album('b', 'Screenshots', 1, 'dcim/screenshots'),
        ]),
        'b',
      );
    });
  });
}
