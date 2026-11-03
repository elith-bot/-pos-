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
    this.spans,
  }) : assert(columns > 0),
       assert(spacing >= 0);

  final int columns;
  final double spacing;
  final List<int>? spans;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProductMasonry(
        columns,
        spacing,
        Directionality.of(context),
        spans,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    (renderObject as _RenderProductMasonry).configure(
      columns,
      spacing,
      Directionality.of(context),
      spans,
    );
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderProductMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  _RenderProductMasonry(this.columns, this.spacing, this.direction, this.spans);

  int columns;
  double spacing;
  TextDirection direction;
  List<int>? spans;

  void configure(
    int count,
    double gap,
    TextDirection textDirection,
    List<int>? newSpans,
  ) {
    if (columns == count &&
        spacing == gap &&
        direction == textDirection &&
        spans == newSpans) {
      return;
    }
    columns = count;
    spacing = gap;
    direction = textDirection;
    spans = newSpans;
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
    double rowHeight = 0;
    var index = 0;
    if (spans != null) {
      while (child != null) {
        child.layout(
          BoxConstraints.tightFor(width: cardWidth),
          parentUsesSize: true,
        );
        final span = spans![index++];
        rowHeight = math.max(
          rowHeight,
          (child.size.height - spacing * (span - 1)) / span,
        );
        child = (child.parentData! as _CardParentData).nextSibling;
      }
      child = firstChild;
    }
    index = 0;
    while (child != null) {
      var column = 0;
      for (var i = 1; i < columns; i++) {
        if (bottoms[i] < bottoms[column]) column = i;
      }
      child.layout(
        BoxConstraints.tightFor(
          width: cardWidth,
          height: spans == null
              ? null
              : rowHeight * spans![index] + spacing * (spans![index] - 1),
        ),
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
      index++;
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
