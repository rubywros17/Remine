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
    this.raised = false,
  });

  final List<ScreenshotItem> items;
  final GlobalKey Function(int id) keyFor;
  final ValueChanged<int>
  onOpen; // 전체 목록 안의 위치(index) = [indexOffset] + 이 그리드 안의 위치

  /// 한 목록을 여러 구역(태그 화면의 "최근 2주"/"그 전")으로 나눠 그릴 때 이 구역이 시작하는 위치.
  final int indexOffset;

  /// 사진을 배경색 받침에 올린 뉴모피즘 볼록 카드([AppShadow.neuRaised], 태그 화면). 바탕이 [AppColors.neuBg]여야 한다.
  final bool raised;

  static const _heights = [230.0, 170.0, 200.0, 250.0, 160.0];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s40),
        child: Center(child: Text('아직 여기엔 아무것도 없어', style: AppText.body)),
      );
    }
    // 볼록 카드는 그림자가 옆 카드 쪽으로 약 26px 번져 간격을 넓힌다.
    final gap = raised ? AppSpacing.s20 : AppSpacing.s12;
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final tile = Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: _Tile(
          key: ValueKey('tile-${items[i].id}'),
          item: items[i],
          height: _heights[(items[i].id + indexOffset + i) % _heights.length],
          anchorKey: keyFor(items[i].id),
          onTap: () => onOpen(indexOffset + i),
          raised: raised,
        ),
      );
      (i.isEven ? left : right).add(tile);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        SizedBox(width: gap),
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
    required this.raised,
  });

  final ScreenshotItem item;
  final double height;

  /// 상세에서 돌아올 때 이 타일이 보이게 스크롤하려고 쓰는 키.
  final GlobalKey anchorKey;
  final VoidCallback onTap;
  final bool raised;

  // 날짜 알약은 카드 바깥 기준 왼쪽 아래 12. 볼록 카드면 받침 여백만큼 사진 안쪽으로 당겨 같은 자리에 둔다.
  static const _pillInset = 12.0;

  @override
  Widget build(BuildContext context) {
    final pillInset = raised
        ? _pillInset - AppShadow.neuRaisedPadding
        : _pillInset;
    final photo = Hero(
      tag: 'screenshot-${item.id}',
      child: CaptureThumb(
        assetId: item.localAssetId,
        seed: item.id,
        radius: raised ? AppRadii.tile : AppRadii.card,
        child: Positioned(
          left: pillInset,
          bottom: pillInset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                formatMonthDay(item.takenAt),
                style: AppText.numBadge(),
              ),
            ),
          ),
        ),
      ),
    );
    return PressableScale(
      onTap: onTap,
      label:
          '${item.summary ?? item.category.label}, ${formatMonthDay(item.takenAt)}',
      child: SizedBox(
        key: anchorKey,
        height: height,
        // 받침은 Hero 밖: 상세로 갈 때 사진만 받침에서 들려 나가고 받침은 자리에 남는다.
        // RepaintBoundary: 블러 그림자를 타일마다 한 번만 그리고 스크롤 중엔 다시 그리지 않게.
        child: raised
            ? RepaintBoundary(
                child: Container(
                  padding: const EdgeInsets.all(AppShadow.neuRaisedPadding),
                  decoration: BoxDecoration(
                    color: AppColors.neuBg,
                    borderRadius: BorderRadius.circular(
                      AppShadow.neuRaisedRadius,
                    ),
                    boxShadow: AppShadow.neuRaised,
                  ),
                  child: photo,
                ),
              )
            : photo,
      ),
    );
  }
}
