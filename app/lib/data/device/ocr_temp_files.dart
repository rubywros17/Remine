import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// OCR 입력용 임시 복사본을 **앱 캐시 폴더 안에서만** 만들고 지운다.
///
/// 사진 원본 경로(MediaStore의 실제 파일)는 이 클래스를 거치지 않고, 원본 바이트만 받아 복사본을 쓴다.
/// [dispose]는 [root] 아래 파일만 지운다 — 원본 경로가 실수로 넘어와도 지우지 않는다.
class OcrTempFiles {
  OcrTempFiles(this.root);

  final Directory root;
  int _seq = 0;

  Future<File> write(Uint8List bytes) async {
    await root.create(recursive: true);
    final file = File(p.join(root.path, 'ocr_${_seq++}.img'));
    return file.writeAsBytes(bytes, flush: true);
  }

  /// [file]이 [root] 안에 있을 때만 지운다. 지웠으면 true.
  Future<bool> dispose(File file) async {
    if (!p.isWithin(root.path, file.path)) return false;
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// 이전 실행이 남긴 복사본 정리(측정 시작 시).
  Future<void> clear() async {
    if (!await root.exists()) return;
    await for (final e in root.list()) {
      if (e is File) await dispose(e);
    }
  }
}
