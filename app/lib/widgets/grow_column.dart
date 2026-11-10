import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 세로로 쌓되, 받은 최소 높이(화면 높이)보다 내용이 짧으면 남는 높이의 일부를 [GrowGap]에 주는 Column.
///
/// - [GrowGap]은 기본 높이 [GrowGap.base]에 (남는 높이 × [GrowGap.share], 최대 [GrowGap.maxExtra])를 더한다.
/// - 그러고도 남는 높이는 맨 아래(마지막 자식 뒤)에 남는다. 내용이 더 길면 간격은 기본값이고, 바깥 스크롤이 처리한다.
/// - 자식은 가로로 꽉 채운다(ListView와 같다).
///
/// [Flutter 메모] Column + Flexible로는 "내용 높이"를 미리 알아야 하는데(고유 높이 계산),
/// 홈의 비율 막대·관심사 카드 안의 LayoutBuilder는 그 계산을 지원하지 않는다. 그래서 자식을 한 번 배치해
/// 높이를 잰 뒤 간격을 정하는 작은 RenderBox를 직접 둔다(레이아웃 한 번, 추가 프레임 없음).
class GrowColumn extends MultiChildRenderObjectWidget {
  const GrowColumn({super.key, super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGrowColumn();
}

/// [GrowColumn] 안의 늘어나는 세로 간격.
class GrowGap extends ParentDataWidget<GrowParentData> {
  const GrowGap(
    this.base, {
    super.key,
    required this.share,
    required this.maxExtra,
  }) : super(child: const SizedBox.shrink());

  final double base;

  /// 남는 높이 중 이 간격이 가져가는 비율.
  final double share;

  /// 기본 높이에 더할 수 있는 최대값.
  final double maxExtra;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as GrowParentData;
    if (data.base != base || data.share != share || data.maxExtra != maxExtra) {
      data
        ..base = base
        ..share = share
        ..maxExtra = maxExtra;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => GrowColumn;
}

/// [GrowColumn] 자식의 배치 정보. [base]가 있으면 [GrowGap]이다.
class GrowParentData extends ContainerBoxParentData<RenderBox> {
  double? base; // null이면 일반 자식
  double share = 0;
  double maxExtra = 0;
}

/// [GrowColumn]의 RenderBox: 일반 자식을 먼저 배치해 높이를 재고, 남는 높이로 간격을 정한다.
class RenderGrowColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GrowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GrowParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GrowParentData) {
      child.parentData = GrowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var used = 0.0; // 일반 자식 높이 + 간격 기본값
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final base = (c.parentData! as GrowParentData).base;
      if (base == null) {
        c.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
        used += c.size.height;
      } else {
        used += base;
      }
    }
    final leftover = math.max(0.0, constraints.minHeight - used);
    var y = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final data = c.parentData! as GrowParentData;
      final base = data.base;
      if (base != null) {
        final h = base + math.min(leftover * data.share, data.maxExtra);
        c.layout(
          BoxConstraints.tightFor(width: width, height: h),
          parentUsesSize: true,
        );
      }
      data.offset = Offset(0, y);
      y += c.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
