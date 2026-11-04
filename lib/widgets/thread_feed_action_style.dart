import 'package:flutter/material.dart';

abstract final class ThreadFeedActionStyle {
  static const iconSize = 20.0;
  static const numberScale = .86;

  static Color color(BuildContext context, {bool liked = false}) {
    final colors = Theme.of(context).colorScheme;
    return Color.lerp(
      colors.surface,
      liked ? colors.primary : colors.onSurfaceVariant,
      .65,
    )!;
  }
}
