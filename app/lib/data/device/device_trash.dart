import 'gallery_reader.dart';
import 'ocr_store.dart';
import 'privacy/local_verdict_store.dart';
import 'trash_store.dart';

/// 휴지통 화면이 쓰는 동작 묶음: 되살리기, 갤러리에서 삭제.
class DeviceTrash {
  DeviceTrash({
    required this.store,
    required this.reader,
    required this.verdicts,
    required this.ocr,
    this.onChanged,
    this.forgetEntries,
  });

  final TrashStore store;
  final GalleryReader reader;
  final LocalVerdictStore verdicts;
  final OcrStore ocr;

  /// 서버 반영 대기를 보내게 한다(서버 연동일 때만). 실패해도 대기열에 남으니 기다리지 않아도 된다.
  final Future<void> Function()? onChanged;

  /// 동기화 기록에서 지운다(서버 연동일 때만).
  final Future<void> Function(Iterable<String> assetIds)? forgetEntries;

  /// 앱에서만 되살린다. 원본은 처음부터 그대로다.
  Future<void> restore(Iterable<String> assetIds) async {
    for (final id in assetIds) {
      await store.restore(id);
    }
    await onChanged?.call();
  }

  /// 시스템 확인창 한 번으로 갤러리 휴지통으로 옮긴다. 사용자가 허용한 장만 앱 기록(휴지통·OCR·판정·서버)에서 지우고,
  /// 취소하면 아무것도 바꾸지 않는다. 옮긴 장수를 돌려준다.
  Future<int> deleteFromGallery(List<String> assetIds) async {
    if (assetIds.isEmpty) return 0;
    final moved = await reader.moveToTrash(assetIds);
    if (moved.isEmpty) return 0;
    await store.markDeleted(moved);
    await forgetEntries?.call(moved);
    for (final id in moved) {
      await ocr.remove(id);
    }
    await verdicts.removeAll(moved);
    await onChanged?.call();
    return moved.length;
  }
}
