import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'section_tabs.dart';

/// Horizontal gestures compete normally with the feed's vertical scrolling.
class LiquidFeedSwitcher extends StatefulWidget {
  const LiquidFeedSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.children,
    this.onPrepare,
    this.header,
    this.onSwitching,
    this.labels = const ['推荐', '热榜'],
  }) : assert(labels.length == children.length),
       assert(selected >= 0 && selected < children.length);
  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onPrepare;
  final List<Widget> children;
  final Widget? header;
  final ValueChanged<bool>? onSwitching;
  final List<String> labels;

  @override
  State<LiquidFeedSwitcher> createState() => _LiquidFeedSwitcherState();
}

class _LiquidFeedSwitcherState extends State<LiquidFeedSwitcher>
    with TickerProviderStateMixin {
  late final AnimationController _position = AnimationController(
    vsync: this,
    value: widget.selected.toDouble(),
    upperBound: (widget.children.length - 1).toDouble(),
  )..addListener(_feedWater);
  final _water = _Flood();
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  double _width = 400;
  double _source = 0;
  bool _dragging = false;
  int _run = 0;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1000000).clamp(0.0, .04);
    _lastTick = elapsed;
    _water.step(dt);
    if (!_dragging && !_position.isAnimating && _water.opacity <= 0) {
      _ticker.stop();
    }
  }

  void _beginWater({int? target}) {
    _source = widget.selected.toDouble();
    _water.begin(fromRight: target != null && target < _source);
    if (!_reduced && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _feedWater() {
    // A full header is the slow-drag release threshold; pages remain 1:1
    // with the finger until release, independently of this shorter fill.
    _water.feed(((_position.value - _source).abs() / .28).clamp(0.0, 1.0));
  }

  @override
  void didUpdateWidget(covariant LiquidFeedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected &&
        !_dragging &&
        !_position.isAnimating &&
        (_position.value - widget.selected).abs() > .001) {
      _beginWater(target: widget.selected);
      // The selected value has already changed; animate from the old page.
      _source = oldWidget.selected.toDouble();
      _water.begin(fromRight: widget.selected < _source);
      _settle(widget.selected, 0);
    }
  }

  void _start(DragStartDetails details) {
    widget.onSwitching?.call(true);
    _run++;
    _position.stop();
    _dragging = true;
    _beginWater();
    for (final target in [widget.selected - 1, widget.selected + 1]) {
      if (target >= 0 && target < widget.children.length) {
        widget.onPrepare?.call(target);
      }
    }
  }

  void _update(DragUpdateDetails details) {
    final next = (_position.value - details.delta.dx / _width).clamp(
      math.max(0.0, _source - 1),
      math.min((widget.children.length - 1).toDouble(), _source + 1),
    );
    if ((next - _source).abs() > .0001 &&
        _water.fromRight != (next < _source)) {
      _water.begin(fromRight: next < _source);
    }
    _position.value = next.toDouble();
  }

  void _end(DragEndDetails details) {
    final velocity = -(details.primaryVelocity ?? 0) / _width;
    final distance = _position.value - widget.selected;
    final towardTarget = distance.sign;
    final directedSpeed = velocity * towardTarget;
    final commit =
        directedSpeed > 1.1 && distance.abs() > .025 ||
        distance.abs() >= .28 && directedSpeed > -.65;
    final target = (widget.selected + towardTarget.toInt()).clamp(
      0,
      widget.children.length - 1,
    );
    _settle(commit ? target : widget.selected, velocity);
  }

  Future<void> _settle(int target, double velocity) async {
    _dragging = false;
    final run = ++_run;
    final remaining = (target - _position.value).abs();
    final milliseconds = (180 + remaining * 160 - velocity.abs() * 18)
        .clamp(140.0, 340.0)
        .round();
    if (_reduced) {
      _position.value = target.toDouble();
    } else {
      try {
        await _position
            .animateTo(
              target.toDouble(),
              duration: Duration(milliseconds: milliseconds),
              curve: Curves.easeOutCubic,
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || run != _run) return;
    if (target != widget.selected) widget.onSelected(target);
    _water.release();
    widget.onSwitching?.call(false);
  }

  void _select(int target) {
    if (target == widget.selected && !_position.isAnimating) return;
    widget.onSwitching?.call(true);
    _position.stop();
    _beginWater(target: target);
    widget.onPrepare?.call(target);
    _settle(target, 0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    _water.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.header != null) widget.header!,
              SectionTabs(
                labels: widget.labels,
                selected: widget.selected,
                onSelected: _select,
              ),
            ],
          ),
          if (!_reduced)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _FloodPainter(
                      _water,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _start,
              onHorizontalDragUpdate: _update,
              onHorizontalDragEnd: _end,
              onHorizontalDragCancel: () {
                // A child long press or vertical scroll can win before a
                // horizontal drag starts. There is then nothing to settle.
                if (_dragging) _settle(widget.selected, 0);
              },
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var index = 0; index < widget.children.length; index++)
                      AnimatedBuilder(
                        key: ValueKey(index),
                        animation: _position,
                        child: RepaintBoundary(child: widget.children[index]),
                        builder: (context, child) {
                          final offset = index - _position.value;
                          final visible = offset.abs() < .9999;
                          return Offstage(
                            offstage: !visible,
                            child: TickerMode(
                              enabled: visible,
                              child: IgnorePointer(
                                ignoring:
                                    _dragging ||
                                    _position.isAnimating ||
                                    index != widget.selected,
                                child: Transform.translate(
                                  offset: Offset(offset * _width, 0),
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// A shallow-water surface: neighboring columns exchange displacement and
/// momentum. The moving flood front supplies energy; no looping wave clock.
class _Flood extends ChangeNotifier {
  static const count = 72;
  final heights = List<double>.filled(count, 0);
  final speeds = List<double>.filled(count, 0);
  double progress = 0;
  double opacity = 0;
  bool fromRight = false;
  bool draining = false;
  double _releaseTime = 0;

  void begin({required bool fromRight}) {
    if (this.fromRight != fromRight || opacity <= 0) {
      heights.fillRange(0, count, 0);
      speeds.fillRange(0, count, 0);
      progress = 0;
    }
    this.fromRight = fromRight;
    draining = false;
    _releaseTime = 0;
    opacity = 1;
  }

  void feed(double value) {
    final change = value - progress;
    if (change.abs() > .0001) {
      final front = (value * (count - 1)).round().clamp(0, count - 1);
      // Momentum is injected at the advancing/retreating front, spreading
      // through the surface and reflecting at the closed end of the bar.
      for (
        var i = math.max(0, front - 4);
        i <= math.min(count - 1, front + 3);
        i++
      ) {
        speeds[i] += change.clamp(-.12, .12) * 360 / (1 + (i - front).abs());
      }
    }
    progress = value;
  }

  void release() {
    draining = true;
    _releaseTime = 0;
  }

  void step(double dt) {
    if (draining) {
      _releaseTime += dt;
      opacity = (1 - math.max(0.0, _releaseTime - .12) / .42).clamp(0.0, 1.0);
    }
    // Bounded substeps keep the spring stable on both 60 Hz and 120 Hz.
    final steps = math.max(1, (dt * 120).ceil());
    final h = dt / steps;
    for (var step = 0; step < steps; step++) {
      for (var i = 0; i < count; i++) {
        final x = i / (count - 1);
        final wet = ((progress * 1.18 - x) / .18).clamp(0.0, 1.0);
        final ramp = wet * wet * (3 - 2 * wet);
        final depth = (17 + 31 * progress) * ramp;
        final left = heights[math.max(0, i - 1)];
        final right = heights[math.min(count - 1, i + 1)];
        final acceleration =
            (depth - heights[i]) * 210 +
            (left + right - 2 * heights[i]) * 1250 -
            speeds[i] * 15;
        speeds[i] += acceleration * h;
      }
      for (var i = 0; i < count; i++) {
        heights[i] = (heights[i] + speeds[i] * h).clamp(-4.0, 56.0);
      }
    }
    notifyListeners();
  }
}

class _FloodPainter extends CustomPainter {
  _FloodPainter(this.water, this.color) : super(repaint: water);
  final _Flood water;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (water.opacity <= 0 || water.progress <= .001 && !water.draining) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (water.fromRight) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final surface = Path();
    final points = <Offset>[];
    for (var i = 0; i < _Flood.count; i++) {
      points.add(
        Offset(
          i * size.width / (_Flood.count - 1),
          size.height * (1 - water.heights[i].clamp(0.0, 56.0) / 42),
        ),
      );
    }
    surface.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1], next = points[i];
      final middle = (previous.dx + next.dx) / 2;
      surface.cubicTo(middle, previous.dy, middle, next.dy, next.dx, next.dy);
    }
    final fill = Path.from(surface)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: .08 * water.opacity),
            color.withValues(alpha: .30 * water.opacity),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      surface,
      Paint()
        ..color = color.withValues(alpha: .60 * water.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      Offset(0, size.height - 1.5),
      Offset(size.width * water.progress, size.height - 1.5),
      Paint()
        ..color = color.withValues(alpha: .8 * water.opacity)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloodPainter old) =>
      old.water != water || old.color != color;
}
