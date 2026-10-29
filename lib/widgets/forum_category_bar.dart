import 'package:flutter/material.dart';

class ForumCategoryHeader extends SliverPersistentHeaderDelegate {
  ForumCategoryHeader({required this.child});
  final Widget child;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: overlapsContent ? 1 : 0,
    child: SizedBox.expand(child: child),
  );

  @override
  bool shouldRebuild(covariant ForumCategoryHeader oldDelegate) => true;
}
