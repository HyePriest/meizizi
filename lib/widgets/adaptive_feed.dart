import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
        SliverPadding(
          padding: padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (start > 0) SliverToBoxAdapter(child: itemBuilder(context, 0)),
              AdaptiveFeedSliver(
                itemCount: end - start,
                itemBuilder: (context, index) =>
                    itemBuilder(context, index + start),
              ),
              if (end < itemCount)
                SliverToBoxAdapter(child: itemBuilder(context, end)),
            ],
          ),
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
      final columns = useTabletLandscape(context)
          ? (constraints.crossAxisExtent / (320 * scale)).floor().clamp(
              1,
              desktop ? 4 : 3,
            )
          : 1;
      if (columns == 1) {
        return SliverList.builder(
          itemCount: itemCount,
          itemBuilder: itemBuilder,
          findChildIndexCallback: findChildIndexCallback,
        );
      }
      return SliverCrossAxisGroup(
        slivers: [
          for (var column = 0; column < columns; column++)
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverPadding(
                padding: EdgeInsets.only(
                  left: column == 0 ? 0 : 8,
                  right: column == columns - 1 ? 0 : 8,
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
      );
    },
  );
}
