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

  /// 사진 카드에 바로 뉴모피즘 그림자([AppShadow.neuRaised]), 날짜 알약엔 작은 뉴모 그림자(태그 화면). 바탕이 [AppColors.neuBg]여야 한다.
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

  @override
  Widget build(BuildContext context) {
    final radius = raised ? AppShadow.neuRaisedRadius : AppRadii.card;
    final pillInset = raised ? 10.0 : 12.0;
    Widget thumb = CaptureThumb(
      assetId: item.localAssetId,
      seed: item.id,
      radius: radius,
      child: Positioned(
        left: pillInset,
        bottom: pillInset,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: raised ? AppShadow.neuRaisedSmall : null,
            // 카테고리 알약과 같은 테두리. DecoratedBox의 테두리는 안쪽에 그려져 알약 크기는 그대로다.
            border: raised
                ? Border.all(
                    color: AppCategoryColors.pillBorder,
                    width: AppCategoryColors.pillBorderWidth,
                  )
                : null,
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
    );
    if (raised) {
      // 그림자는 Hero 안: 상세로 갈 때 빈 자리에 그림자 틀만 남지 않게.
      // RepaintBoundary: 블러 그림자를 타일마다 한 번만 그리고 스크롤 중엔 다시 그리지 않게.
      thumb = RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: AppShadow.neuRaised,
          ),
          child: thumb,
        ),
      );
    }
    return PressableScale(
      onTap: onTap,
      label:
          '${item.summary ?? item.category.label}, ${formatMonthDay(item.takenAt)}',
      child: SizedBox(
        key: anchorKey,
        height: height,
        child: Hero(tag: 'screenshot-${item.id}', child: thumb),
      ),
    );
  }
}
