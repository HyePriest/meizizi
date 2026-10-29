import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'page_drag.dart';

/// Owns zoom gestures while delegating page motion to native scroll physics.
class ImageGallery extends StatefulWidget {
  const ImageGallery({
    super.key,
    required this.itemCount,
    required this.initialPage,
    required this.itemBuilder,
    required this.onPageChanged,
  });
  final int itemCount, initialPage;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;

  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery>
    with TickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.initialPage);
  late final _pageDrag = PageDrag(_pages);
  late final _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(_animateZoom);
  late final _panAnimation = AnimationController.unbounded(vsync: this)
    ..addListener(_animatePan);
  Offset _panFrom = Offset.zero, _panDirection = Offset.zero;
  ScrollHoldController? _pageHold;
  late int _index = widget.initialPage;
  double _scale = 1, _startScale = 1;
  Offset _offset = Offset.zero, _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero, _tap = Offset.zero;
  Offset _lastFocal = Offset.zero;
  double _zoomFrom = 1, _zoomTo = 1;
  Offset _offsetFrom = Offset.zero, _offsetTo = Offset.zero;
  int _origin = 0;
  bool _zoomGesture = false;
  bool? _horizontal;
  Size _size = Size.zero;

  Offset _bounded(Offset offset, double scale) => Offset(
    offset.dx.clamp(
      -_size.width * (scale - 1) / 2,
      _size.width * (scale - 1) / 2,
    ),
    offset.dy.clamp(
      -_size.height * (scale - 1) / 2,
      _size.height * (scale - 1) / 2,
    ),
  );

  void _start(ScaleStartDetails details) {
    _panAnimation.stop();
    _zoomAnimation.stop();
    _origin = (_pages.page ?? _index.toDouble()).round();
    // Stop a settling page exactly where it is so another swipe can take over.
    _pageHold = _pages.position.hold(() => _pageHold = null);
    _startFocal = details.localFocalPoint;
    _lastFocal = _startFocal;
    _startScale = _scale;
    _startOffset = _offset;
    _zoomGesture = details.pointerCount > 1 || _scale > 1.01;
    _horizontal = null;
  }

  void _update(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) _zoomGesture = true;
    if (_zoomGesture) {
      _pageDrag.cancel();
      _pageHold?.cancel();
      // A second finger changes this gesture to zoom, never to another page.
      if ((_pages.page! - _origin).abs() > .001) _pages.jumpToPage(_origin);
      final scale = (_startScale * details.scale).clamp(1.0, 8.0);
      final center = _size.center(Offset.zero);
      final anchor = (_startFocal - center - _startOffset) / _startScale;
      setState(() {
        _scale = scale;
        _offset = _bounded(
          details.localFocalPoint - center - anchor * scale,
          scale,
        );
      });
      return;
    }
    final delta = details.localFocalPoint - _startFocal;
    final movement = details.localFocalPoint - _lastFocal;
    _lastFocal = details.localFocalPoint;
    if (delta.distance > 2) _horizontal ??= delta.dx.abs() > delta.dy.abs();
    if (_horizontal != true) return;
    _pageDrag.update(movement, details.localFocalPoint);
    // Creating the drag replaces the hold; do not cancel it into a ballistic.
    _pageHold = null;
  }

  void _end(ScaleEndDetails details) {
    _pageHold?.cancel();
    _pageHold = null;
    if (!_zoomGesture) {
      _pageDrag.end(details.velocity);
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    if (_scale <= 1.01 ||
        speed < 50 ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _panFrom = _offset;
    _panDirection = velocity / speed;
    _panAnimation.animateWith(
      FrictionSimulation(0.0000135, 0, speed.clamp(0.0, 8000.0)),
    );
  }

  void _animatePan() {
    final next = _bounded(
      _panFrom + _panDirection * _panAnimation.value,
      _scale,
    );
    if (next == _offset) return;
    setState(() => _offset = next);
  }

  void _animateZoom() {
    final t = Curves.easeInOutCubic.transform(_zoomAnimation.value);
    setState(() {
      _scale = _zoomFrom + (_zoomTo - _zoomFrom) * t;
      _offset = Offset.lerp(_offsetFrom, _offsetTo, t)!;
    });
  }

  void _doubleTap() {
    _panAnimation.stop();
    final scale = _scale > 1.01 ? 1.0 : 3.0;
    _zoomFrom = _scale;
    _offsetFrom = _offset;
    _zoomTo = scale;
    _offsetTo = scale == 1
        ? Offset.zero
        : _bounded((_size.center(Offset.zero) - _tap) * 2, scale);
    if (MediaQuery.disableAnimationsOf(context)) {
      _zoomAnimation.stop();
      setState(() {
        _scale = _zoomTo;
        _offset = _offsetTo;
      });
    } else {
      _zoomAnimation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _panAnimation.dispose();
    _zoomAnimation.dispose();
    _pageDrag.cancel();
    _pageHold?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return Listener(
        onPointerDown: (_) => _panAnimation.stop(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _start,
          onScaleUpdate: _update,
          onScaleEnd: _end,
          onDoubleTapDown: (details) => _tap = details.localPosition,
          onDoubleTap: _doubleTap,
          child: PageView.builder(
            controller: _pages,
            physics: const PageScrollPhysics(
              parent: NeverScrollableScrollPhysics(),
            ),
            itemCount: widget.itemCount,
            onPageChanged: (index) {
              setState(() {
                _index = index;
                _scale = 1;
                _offset = Offset.zero;
              });
              widget.onPageChanged(index);
            },
            itemBuilder: (context, index) => ClipRect(
              child: Transform(
                key: ValueKey('gallery-transform-$index'),
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(
                    index == _index ? _offset.dx : 0,
                    index == _index ? _offset.dy : 0,
                    0,
                    1,
                  )
                  ..scaleByDouble(
                    index == _index ? _scale : 1,
                    index == _index ? _scale : 1,
                    1,
                    1,
                  ),
                child: RepaintBoundary(
                  child: SizedBox.expand(
                    child: widget.itemBuilder(context, index),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
