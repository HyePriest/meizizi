import 'package:flutter/material.dart';

import '../data/theme_colors.dart';

/// 列表条目只共用外层分隔，内容和交互由各板块负责。
class FeedListItem extends StatelessWidget {
  const FeedListItem({super.key, required this.child, this.separatorGap = 10});

  final Widget child;
  final double separatorGap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      child,
      Padding(
        padding: EdgeInsets.only(top: separatorGap),
        child: Container(
          height: 7,
          color: homeSeparatorColor(Theme.of(context)),
        ),
      ),
    ],
  );
}
