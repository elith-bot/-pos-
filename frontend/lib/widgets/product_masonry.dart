import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Places each card in the shortest column using its actual laid-out height.
/// Images, wrapped names and accessibility text sizes need no height estimates.
class ProductMasonry extends MultiChildRenderObjectWidget {
  const ProductMasonry({
    super.key,
    required this.columns,
    required super.children,
    this.spacing = 12,
  }) : assert(columns > 0),
       assert(spacing >= 0);

  final int columns;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProductMasonry(columns, spacing, Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    (renderObject as _RenderProductMasonry).configure(
      columns,
      spacing,
      Directionality.of(context),
    );
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderProductMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  _RenderProductMasonry(this.columns, this.spacing, this.direction);

  int columns;
  double spacing;
  TextDirection direction;

  void configure(int count, double gap, TextDirection textDirection) {
    if (columns == count && spacing == gap && direction == textDirection) {
      return;
    }
    columns = count;
    spacing = gap;
    direction = textDirection;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cardWidth = math.max(
      0.0,
      (width - spacing * (columns - 1)) / columns,
    );
    final bottoms = List<double>.filled(columns, 0);
    var child = firstChild;
    while (child != null) {
      var column = 0;
      for (var i = 1; i < columns; i++) {
        if (bottoms[i] < bottoms[column]) column = i;
      }
      child.layout(
        BoxConstraints.tightFor(width: cardWidth),
        parentUsesSize: true,
      );
      final parentData = child.parentData! as _CardParentData;
      final x = column * (cardWidth + spacing);
      parentData.offset = Offset(
        direction == TextDirection.rtl ? width - cardWidth - x : x,
        bottoms[column],
      );
      bottoms[column] += child.size.height + spacing;
      child = parentData.nextSibling;
    }
    final height = bottoms.reduce(math.max);
    size = constraints.constrain(Size(width, math.max(0, height - spacing)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
