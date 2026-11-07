import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'desktop_layout.dart';

bool useTabletLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (defaultTargetPlatform == TargetPlatform.windows) return size.width >= 720;
  return size.shortestSide >= 600 && size.width > size.height;
}

/// A single viewport keeps the scroll position when rotating between layouts.
class AdaptiveFeedView extends StatelessWidget {
  const AdaptiveFeedView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.padding = EdgeInsets.zero,
    this.fullWidthFirst = false,
    this.fullWidthLast = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final ScrollPhysics physics;
  final EdgeInsetsGeometry padding;
  final bool fullWidthFirst, fullWidthLast;

  @override
  Widget build(BuildContext context) {
    final start = fullWidthFirst && itemCount > 0 ? 1 : 0;
    final end = fullWidthLast && itemCount > start ? itemCount - 1 : itemCount;
    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            // Desktop: past [desktopFeedWidth], leave margins at the sides.
            // Padding (not a narrower box) keeps the margins scrollable.
            final gutter = desktopGutter(
              constraints.crossAxisExtent,
              desktopFeedWidth,
            );
            return SliverPadding(
              padding: padding.add(EdgeInsets.symmetric(horizontal: gutter)),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (start > 0)
                    SliverToBoxAdapter(child: itemBuilder(context, 0)),
                  AdaptiveFeedSliver(
                    itemCount: end - start,
                    itemBuilder: (context, index) =>
                        itemBuilder(context, index + start),
                  ),
                  if (end < itemCount)
                    SliverToBoxAdapter(child: itemBuilder(context, end)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Each lazy column stacks cards at their natural height. Stable round-robin
/// assignment keeps existing cards in their column when another page arrives.
class AdaptiveFeedSliver extends StatelessWidget {
  const AdaptiveFeedSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter? findChildIndexCallback;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
        1.0,
        1.5,
      );
      final desktop = defaultTargetPlatform == TargetPlatform.windows;
      final gutter = desktopGutter(
        constraints.crossAxisExtent,
        desktopFeedWidth,
      );
      final extent = constraints.crossAxisExtent - 2 * gutter;
      // Desktop cards are separate surfaces and need a wider gap.
      final gap = desktop ? 10.0 : 8.0;
      final columns = useTabletLandscape(context)
          ? (extent / (320 * scale)).floor().clamp(1, desktop ? 4 : 3)
          : 1;
      Widget centered(Widget sliver) => gutter == 0
          ? sliver
          : SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: sliver,
            );
      if (columns == 1) {
        return centered(
          SliverList.builder(
            itemCount: itemCount,
            itemBuilder: itemBuilder,
            findChildIndexCallback: findChildIndexCallback,
          ),
        );
      }
      return centered(
        SliverCrossAxisGroup(
          slivers: [
            for (var column = 0; column < columns; column++)
              SliverCrossAxisExpanded(
                flex: 1,
                sliver: SliverPadding(
                  padding: EdgeInsets.only(
                    left: column == 0 ? 0 : gap,
                    right: column == columns - 1 ? 0 : gap,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, row) =>
                          itemBuilder(context, row * columns + column),
                      childCount: (itemCount + columns - 1 - column) ~/ columns,
                      semanticIndexCallback: (_, row) => row * columns + column,
                      findChildIndexCallback: findChildIndexCallback == null
                          ? null
                          : (key) {
                              final index = findChildIndexCallback!(key);
                              return index != null && index % columns == column
                                  ? index ~/ columns
                                  : null;
                            },
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
