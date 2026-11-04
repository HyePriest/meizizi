import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<void> shatterRemove(
  GlobalKey? key,
  Future<void> Function() remove, {
  bool bricks = false,
}) async {
  final context = key?.currentContext;
  if (context == null || MediaQuery.disableAnimationsOf(context)) {
    await remove();
    return;
  }
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) {
    await remove();
    return;
  }
  final boundary = context.findRenderObject();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (boundary is! RenderRepaintBoundary ||
      overlay == null ||
      !boundary.hasSize) {
    await remove();
    return;
  }
  ui.Image snapshot;
  try {
    snapshot = await boundary.toImage(pixelRatio: 1.5);
  } catch (_) {
    await remove();
    return;
  }
  if (!context.mounted || !boundary.attached) {
    snapshot.dispose();
    await remove();
    return;
  }
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final rect =
      overlayBox.globalToLocal(boundary.localToGlobal(Offset.zero)) &
      boundary.size;
  final done = Completer<void>();
  final start = Completer<void>();
  final entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(
        child: _ShatterLayer(
          image: snapshot,
          bricks: bricks,
          rect: rect,
          start: start.future,
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    if (bricks) start.complete();
    await remove();
    if (!bricks) start.complete();
    await done.future;
  } finally {
    entry.remove();
    entry.dispose();
    snapshot.dispose();
  }
}

class _ShatterLayer extends StatefulWidget {
  const _ShatterLayer({
    required this.image,
    required this.bricks,
    required this.rect,
    required this.start,
    required this.onDone,
  });
  final bool bricks;
  final ui.Image image;
  final Rect rect;
  final Future<void> start;
  final VoidCallback onDone;
  @override
  State<_ShatterLayer> createState() => _ShatterLayerState();
}

class _ShatterLayerState extends State<_ShatterLayer>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  @override
  void initState() {
    super.initState();
    widget.start.then((_) async {
      if (!mounted) return;
      await _motion.forward();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (_, _) => CustomPaint(
      painter: _ShatterPainter(
        widget.image,
        widget.rect,
        _motion.value,
        widget.bricks,
      ),
    ),
  );
}

class _ShatterPainter extends CustomPainter {
  final bool bricks;
  const _ShatterPainter(this.image, this.rect, this.t, this.bricks);
  final ui.Image image;
  final Rect rect;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(73);
    final rows = (rect.height / 65).ceil().clamp(2, 16);
    const columns = 6;
    final w = rect.width / columns, h = rect.height / rows;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: (1 - t).clamp(0.0, 1.0));
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        for (var half = 0; half < (bricks ? 1 : 2); half++) {
          final a = Offset(x * w, y * h), b = Offset((x + 1) * w, y * h);
          final c = Offset((x + 1) * w, (y + 1) * h),
              d = Offset(x * w, (y + 1) * h);
          final center = Offset((x + .5) * w, (y + .5) * h);
          final points = bricks
              ? [a, b, c, d]
              : (half == 0 ? [a, b, c] : [a, c, d]);
          final dx =
              (center.dx - rect.width / 2) * .55 +
              (random.nextDouble() - .5) * 75;
          final dy = -25 - random.nextDouble() * 55;
          final angle = (random.nextDouble() - .5) * 1.3;
          canvas.save();
          canvas.translate(
            rect.left + center.dx + dx * t,
            rect.top + center.dy + dy * t + 130 * t * t,
          );
          canvas.rotate(angle * t * (bricks ? .15 : 1));
          canvas.translate(-center.dx, -center.dy);
          canvas.clipPath(Path()..addPolygon(points, true));
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Offset.zero & rect.size,
            paint,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShatterPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.image != image;
}
