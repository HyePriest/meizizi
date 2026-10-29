import 'package:flutter/material.dart';

enum FeedGlyph { upvote, comment, stairs, brick, workGlove, pencil }

class FeedIcon extends StatelessWidget {
  const FeedIcon(this.glyph, {super.key, this.filled = false, this.size = 22});
  final FeedGlyph glyph;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) => glyph == FeedGlyph.workGlove
      ? SizedBox(
          width: size,
          height: size,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: size / .7,
              maxHeight: size / .7,
              child: Image.asset(
                'assets/badges/work-glove.png',
                width: size,
                height: size / .7,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        )
      : CustomPaint(
          size: Size.square(size),
          painter: _FeedIconPainter(
            glyph,
            filled,
            IconTheme.of(context).color ??
                Theme.of(context).colorScheme.onSurface,
          ),
        );
}

class _FeedIconPainter extends CustomPainter {
  const _FeedIconPainter(this.glyph, this.filled, this.color);
  final FeedGlyph glyph;
  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path();
    if (glyph == FeedGlyph.pencil) {
      canvas.translate(12, 12);
      canvas.rotate(.72);
      canvas.translate(-12, -12);
      final barrel = RRect.fromRectAndRadius(
        const Rect.fromLTRB(8.5, 5, 15.5, 17),
        const Radius.circular(.6),
      );
      canvas.drawRRect(
        barrel,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xffd78106), Color(0xffffd45b), Color(0xffefa20b)],
          ).createShader(const Rect.fromLTRB(8.5, 5, 15.5, 17)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(8.5, 1, 15.5, 5),
          const Radius.circular(1.5),
        ),
        Paint()..color = const Color(0xffe76b78),
      );
      canvas.drawRect(
        const Rect.fromLTRB(8.5, 4.5, 15.5, 6.5),
        Paint()..color = const Color(0xff7a8a99),
      );
      canvas.drawRect(
        const Rect.fromLTRB(8.5, 4.8, 15.5, 5.5),
        Paint()..color = const Color(0xffdce6ed),
      );
      canvas.drawPath(
        Path()
          ..moveTo(8.5, 17)
          ..lineTo(15.5, 17)
          ..lineTo(12, 23)
          ..close(),
        Paint()..color = const Color(0xffe5bc86),
      );
      canvas.drawPath(
        Path()
          ..moveTo(10.7, 20.8)
          ..lineTo(13.3, 20.8)
          ..lineTo(12, 23)
          ..close(),
        Paint()..color = const Color(0xff283341),
      );
      canvas.drawLine(
        const Offset(10.2, 7.3),
        const Offset(10.2, 16),
        Paint()
          ..color = const Color(0xffffeb97)
          ..strokeWidth = .8,
      );
      canvas.restore();
      return;
    } else if (glyph == FeedGlyph.upvote) {
      path.moveTo(12, 2.5);
      path.lineTo(21, 12);
      path.lineTo(15.5, 12);
      path.lineTo(15.5, 21);
      path.lineTo(8.5, 21);
      path.lineTo(8.5, 12);
      path.lineTo(3, 12);
      path.close();
    } else if (glyph == FeedGlyph.comment) {
      path.moveTo(12, 3.5);
      path.cubicTo(17.6, 3.5, 22, 6.8, 22, 11.2);
      path.cubicTo(22, 15.6, 17.6, 19, 12, 19);
      path.cubicTo(10.7, 19, 9.5, 18.8, 8.4, 18.5);
      path.lineTo(3.5, 21.2);
      path.lineTo(4.6, 16.4);
      path.cubicTo(2.9, 15, 2, 13.2, 2, 11.2);
      path.cubicTo(2, 6.8, 6.4, 3.5, 12, 3.5);
      path.close();
    } else if (glyph == FeedGlyph.brick) {
      path.moveTo(2.5, 9);
      path.lineTo(15.5, 4.5);
      path.lineTo(21.5, 8);
      path.lineTo(21.5, 15);
      path.lineTo(8.5, 19.5);
      path.lineTo(2.5, 16);
      path.close();
      path.moveTo(2.5, 9);
      path.lineTo(8.5, 12.5);
      path.lineTo(21.5, 8);
      path.moveTo(8.5, 12.5);
      path.lineTo(8.5, 19.5);
    } else {
      path.moveTo(3, 21);
      path.lineTo(3, 16);
      path.lineTo(9, 16);
      path.lineTo(9, 10);
      path.lineTo(15, 10);
      path.lineTo(15, 4);
      path.lineTo(21, 4);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FeedIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      filled != oldDelegate.filled ||
      color != oldDelegate.color;
}
