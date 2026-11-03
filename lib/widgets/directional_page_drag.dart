import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'page_drag.dart';

/// A horizontal drag that only wins when the finger moves mostly sideways.
///
/// The stock recognizer accepts as soon as the horizontal movement passes the
/// touch slop, so a slightly slanted vertical scroll can switch pages. Here the
/// horizontal movement must also be [ratio] times the vertical one; anything
/// steeper is left to the vertical list.
class DirectionalHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  DirectionalHorizontalDragRecognizer({super.debugOwner, this.ratio = 1.7});

  /// 1.7 accepts swipes within about 30° of horizontal.
  final double ratio;

  final _origins = <int, Offset>{};
  Offset _movement = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _origins[event.pointer] = event.position;
    _movement = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    // Record before super, which decides acceptance during this same event.
    final origin = _origins[event.pointer];
    if (event is PointerMoveEvent && origin != null) {
      _movement = event.position - origin;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _origins.remove(event.pointer);
    }
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      ) &&
      _movement.dx.abs() > _movement.dy.abs() * ratio;

  @override
  void dispose() {
    _origins.clear();
    super.dispose();
  }
}

/// Routes mostly-horizontal swipes over [child] to [drag].
class DirectionalPageDragArea extends StatelessWidget {
  const DirectionalPageDragArea({
    super.key,
    required this.drag,
    required this.child,
  });

  final PageDrag drag;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      DirectionalHorizontalDragRecognizer:
          GestureRecognizerFactoryWithHandlers<
            DirectionalHorizontalDragRecognizer
          >(
            () => DirectionalHorizontalDragRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onUpdate = (details) =>
                  drag.update(details.delta, details.globalPosition)
              ..onEnd = (details) => drag.end(details.velocity)
              ..onCancel = drag.cancel,
          ),
    },
    child: child,
  );
}
