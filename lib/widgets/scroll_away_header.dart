import 'package:flutter/material.dart';

class ScrollAwayHeader extends StatelessWidget {
  const ScrollAwayHeader({
    super.key,
    this.offset = 0,
    required this.child,
    this.height = 48,
  });
  final double offset;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ClipRect(
      child: SizedBox(
        height: height,
        child: IgnorePointer(
          ignoring: offset >= height,
          child: Transform.translate(
            offset: Offset(0, -offset.clamp(0.0, height)),
            child: child,
          ),
        ),
      ),
    ),
  );
}
