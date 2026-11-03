import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// With 14px card padding and 12px grid spacing, the photo card occupies
/// exactly two equivalent text-only cards. Measures actual text scaling.
class ProductPhotoBody extends MultiChildRenderObjectWidget {
  ProductPhotoBody({super.key, required Widget image, required Widget body})
    : super(children: [image, body]);
  @override
  RenderObject createRenderObject(BuildContext context) => _PhotoBody();
}

class _PhotoData extends ContainerBoxParentData<RenderBox> {}

class _PhotoBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PhotoData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PhotoData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PhotoData) child.parentData = _PhotoData();
  }

  @override
  void performLayout() {
    final body = lastChild!, photo = firstChild!;
    body.layout(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      parentUsesSize: true,
    );
    final photoHeight = body.size.height + 28;
    photo.layout(
      BoxConstraints.tightFor(width: constraints.maxWidth, height: photoHeight),
    );
    (body.parentData! as _PhotoData).offset = Offset(0, photoHeight + 12);
    size = constraints.constrain(
      Size(constraints.maxWidth, photoHeight + 12 + body.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
