import 'dart:typed_data';

/// JPEG에서 메타데이터 세그먼트(EXIF·GPS가 든 APP1, XMP, APP13 등)를 지운다.
///
/// 압축 라이브러리에 `keepExif: false`를 주지만, 서버로 나가는 바이트는 **여기서 한 번 더** 걸러
/// 라이브러리 동작이나 버전에 기대지 않는다. 이미지 디코딩 없이 세그먼트 헤더만 훑으므로 가볍다.
///
/// 남기는 것: SOI, APP0(JFIF), APP2(ICC 색 프로파일), DQT/SOF/DHT 등 화질·디코딩에 필요한 세그먼트와 스캔 데이터.
/// JPEG이 아니거나 구조가 깨졌으면 null(보내지 않는다).
Uint8List? stripJpegMetadata(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var i = 2;
  while (i + 4 <= jpeg.length) {
    if (jpeg[i] != 0xFF) return null;
    final marker = jpeg[i + 1];
    if (marker == 0xFF) {
      i++; // 채움 바이트
      continue;
    }
    if (marker == 0xDA) {
      // SOS: 이후는 압축된 이미지 데이터(끝까지 그대로 복사).
      out.add(Uint8List.sublistView(jpeg, i));
      return out.toBytes();
    }
    final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (length < 2 || i + 2 + length > jpeg.length) return null;
    final drop =
        marker == 0xE1 || // APP1: EXIF, XMP
        marker == 0xED || // APP13: Photoshop/IPTC
        marker == 0xFE || // COM: 주석
        (marker >= 0xE3 && marker <= 0xEF) || // 그 밖의 APPn
        marker == 0xE0 && !_isJfif(jpeg, i); // APP0이 JFIF가 아니면(예: JFXX 썸네일)
    if (!drop) out.add(Uint8List.sublistView(jpeg, i, i + 2 + length));
    i += 2 + length;
  }
  return null;
}

bool _isJfif(Uint8List b, int i) =>
    i + 9 <= b.length &&
    b[i + 4] == 0x4A && // J
    b[i + 5] == 0x46 && // F
    b[i + 6] == 0x49 && // I
    b[i + 7] == 0x46 && // F
    b[i + 8] == 0x00;

/// 테스트·방어 확인용: 메타데이터 세그먼트(EXIF/XMP 등)가 남아 있는지.
bool jpegHasMetadata(Uint8List jpeg) {
  final stripped = stripJpegMetadata(jpeg);
  return stripped == null || stripped.length != jpeg.length;
}
