import 'dart:math' as math;

import 'package:flutter/material.dart';

class BowShareButton extends StatefulWidget {
  const BowShareButton({
    super.key,
    required this.onShare,
    this.size = 28,
    this.compact = false,
    this.color,
    this.visualSize,
    this.tooltip = '转发',
  });
  final VoidCallback onShare;
  final double size;
  final bool compact;
  final Color? color;
  final double? visualSize;
  final String tooltip;

  @override
  State<BowShareButton> createState() => _BowShareButtonState();
}

class _BowShareButtonState extends State<BowShareButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _waiting = false, _away = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waiting) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _away = true;
    } else if (state == AppLifecycleState.resumed && _away) {
      _waiting = _away = false;
      if (!MediaQuery.disableAnimationsOf(context)) _flight.forward(from: 0);
    }
  }

  void _share() {
    if (_waiting && _away) return;
    _waiting = true;
    _away = false;
    _flight.reset();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onShare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    padding: widget.compact ? EdgeInsets.zero : const EdgeInsets.all(8),
    constraints: widget.compact
        ? const BoxConstraints(minWidth: 40, minHeight: 40)
        : null,
    tooltip: widget.tooltip,
    onPressed: _share,
    color: widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    icon: AnimatedBuilder(
      animation: _flight,
      builder: (context, _) => Transform.scale(
        scale: (widget.visualSize ?? widget.size) / widget.size,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _BowPainter(
            _flight.value,
            widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

class _BowPainter extends CustomPainter {
  const _BowPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress == 1 ? 0.0 : progress;
    final release = Curves.easeOut.transform((t / .24).clamp(0.0, 1.0));
    final reload = ((t - .75) / .25).clamp(0.0, 1.0);
    final pull = -6 + 8 * release * (1 - reload);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 28);
    canvas.rotate(-math.pi / 4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(1, -11)
        ..cubicTo(13, -6, 13, 6, 1, 11),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(1, -11)
        ..lineTo(pull, 0)
        ..lineTo(1, 11),
      paint,
    );
    void arrow(double x, double opacity) {
      final ink = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(Offset(-10 + x, 0), Offset(13 + x, 0), ink);
      canvas.drawPath(
        Path()
          ..moveTo(8 + x, -4)
          ..lineTo(13 + x, 0)
          ..lineTo(8 + x, 4),
        ink,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-10 + x, -3)
          ..lineTo(-7 + x, 0)
          ..lineTo(-10 + x, 3),
        ink,
      );
    }

    if (t == 0) {
      arrow(0, 1);
    } else {
      arrow(30 * Curves.easeInCubic.transform(t), (1 - t / .8).clamp(0.0, 1.0));
      if (reload > 0) arrow(0, reload);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BowPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
