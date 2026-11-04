import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Bridges an externally owned gesture to native page scrolling.
/// The scroll position still owns velocity, bounds and page snapping.
class PageDrag {
  PageDrag(this.controller);
  final PageController controller;
  Drag? _drag;

  void update(Offset delta, Offset position) {
    if (!controller.hasClients) return;
    _drag ??= controller.position.drag(
      DragStartDetails(localPosition: position, globalPosition: position),
      () => _drag = null,
    );
    _drag?.update(
      DragUpdateDetails(
        delta: Offset(delta.dx, 0),
        primaryDelta: delta.dx,
        localPosition: position,
        globalPosition: position,
      ),
    );
  }

  void end(Velocity velocity) {
    final drag = _drag;
    _drag = null;
    drag?.end(
      DragEndDetails(
        velocity: Velocity(
          pixelsPerSecond: Offset(velocity.pixelsPerSecond.dx, 0),
        ),
        primaryVelocity: velocity.pixelsPerSecond.dx,
      ),
    );
  }

  void cancel() {
    final drag = _drag;
    _drag = null;
    drag?.cancel();
  }
}
