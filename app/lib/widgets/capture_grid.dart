import 'package:flutter/material.dart';

import '../core/helpers.dart';
import '../core/tokens.dart';
import '../models/screenshot_item.dart';
import 'capture_thumb.dart';
import 'pressable_scale.dart';

/// 캡처 그리드: 두 열로 나누고 높이를 달리해 엇갈리게 쌓는다(카테고리·태그 화면).
/// (한 화면에 담기는 개수가 적어 단순 Column 두 개로 만들었다.
/// 실제 서버 연동에서 수백 장이 되면 지연 로딩 그리드로 바꾼다.)
class CaptureGrid extends StatelessWidget {
  const CaptureGrid({
    super.key,
    required this.items,
    required this.keyFor,
    required this.onOpen,
    this.indexOffset = 0,
  });

  final List<ScreenshotItem> items;
  final GlobalKey Function(int id) keyFor;
  final ValueChanged<int>
  onOpen; // 전체 목록 안의 위치(index) = [indexOffset] + 이 그리드 안의 위치

  /// 한 목록을 여러 구역(태그 화면의 "최근 2주"/"그 전")으로 나눠 그릴 때 이 구역이 시작하는 위치.
  final int indexOffset;

  static const _heights = [230.0, 170.0, 200.0, 250.0, 160.0];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s40),
        child: Center(child: Text('아직 여기엔 아무것도 없어', style: AppText.body)),
      );
    }
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final tile = Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
        child: _Tile(
          key: ValueKey('tile-${items[i].id}'),
          item: items[i],
          height: _heights[(items[i].id + indexOffset + i) % _heights.length],
          anchorKey: keyFor(items[i].id),
          onTap: () => onOpen(indexOffset + i),
        ),
      );
      (i.isEven ? left : right).add(tile);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: AppSpacing.s12),
        // 오른쪽 열을 아래로 밀어 엇갈리게
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Column(children: right),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.height,
    required this.anchorKey,
    required this.onTap,
  });

  final ScreenshotItem item;
  final double height;

  /// 상세에서 돌아올 때 이 타일이 보이게 스크롤하려고 쓰는 키.
  final GlobalKey anchorKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      label:
          '${item.summary ?? item.category.label}, ${formatMonthDay(item.takenAt)}',
      child: SizedBox(
        key: anchorKey,
        height: height,
        child: Hero(
          tag: 'screenshot-${item.id}',
          child: CaptureThumb(
            assetId: item.localAssetId,
            seed: item.id,
            child: Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    formatMonthDay(item.takenAt),
                    style: AppText.numBadge(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
