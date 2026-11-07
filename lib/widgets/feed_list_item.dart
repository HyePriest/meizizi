import 'package:flutter/material.dart';

import '../data/theme_colors.dart';
import 'desktop_layout.dart';

/// 列表条目只共用外层分隔，内容和交互由各板块负责。
///
/// 电脑版改为带浅色底的圆角卡片，并为「鼠标移上才显示」的按钮提供悬停状态。
class FeedListItem extends StatelessWidget {
  const FeedListItem({super.key, required this.child, this.separatorGap = 10});

  final Widget child;
  final double separatorGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DesktopHoverRegion(
          child: Material(
            color: desktopCardColor(theme),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              child: child,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        child,
        Padding(
          padding: EdgeInsets.only(top: separatorGap),
          child: Container(height: 7, color: homeSeparatorColor(theme)),
        ),
      ],
    );
  }
}
