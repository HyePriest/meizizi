import 'package:flutter/material.dart';

enum PlacementResult { located, notLocated, cancelled }

/// Owns a placement from loading through layout, including entry visibility.
/// Gesture cancellation releases it immediately; only its owner may finish it.
class ReadingViewport extends ChangeNotifier {
  final rows = <String, GlobalKey>{};
  final key = GlobalKey();
  int _revision = 0;
  int? _active;
  bool _hidden = false;
  bool get restoring => _active != null;
  bool get hidden => _hidden;

  int begin({bool hideContent = false}) {
    _active = ++_revision;
    _hidden = hideContent;
    notifyListeners();
    return _revision;
  }

  bool isCurrent(int token) => token == _active;
  void finish(int token) {
    if (!isCurrent(token)) return;
    _active = null;
    _hidden = false;
    notifyListeners();
  }

  void cancel() {
    if (_active == null) return;
    _revision++;
    _active = null;
    _hidden = false;
    notifyListeners();
  }

  ({String id, double delta})? visibleAnchor({double topInset = 0}) {
    final viewport = key.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached || !viewport.hasSize)
      return null;
    final top = viewport.localToGlobal(Offset.zero).dy + topInset;
    String? id;
    double best = double.infinity;
    for (final entry in rows.entries) {
      final row = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (row == null || !row.attached || !row.hasSize) continue;
      final y = row.localToGlobal(Offset.zero).dy - top;
      if (y + row.size.height <= 0 || y >= viewport.size.height - topInset)
        continue;
      if (y < best) {
        best = y;
        id = entry.key;
      }
    }
    return id == null ? null : (id: id, delta: -best);
  }

  Future<PlacementResult> placeOffset({
    required int token,
    required ScrollController scroll,
    required bool Function() valid,
    required double? Function() offset,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!isCurrent(token) || !valid()) return PlacementResult.cancelled;
    if (!scroll.hasClients) return PlacementResult.notLocated;
    final target = offset();
    if (target == null) return PlacementResult.notLocated;
    scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
    return PlacementResult.located;
  }

  Future<PlacementResult> locate({
    required int token,
    required ScrollController scroll,
    required String id,
    required bool Function() valid,
    required bool building,
    required bool firstFloor,
    required bool nested,
    double delta = 0,
    double topInset = 0,
  }) async {
    bool current() => isCurrent(token) && valid() && scroll.hasClients;
    // Preserve the existing bounded traversal of lazily built rows.
    for (var attempt = 0; attempt < 35; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return PlacementResult.cancelled;
      if (building && firstFloor && delta == 0) {
        scroll.jumpTo(0);
        return PlacementResult.located;
      }
      final target = rows[id]?.currentContext;
      if (target != null && target.mounted) {
        if (scroll.position.maxScrollExtent > 0) {
          await Scrollable.ensureVisible(
            target,
            alignment: 0,
            alignmentPolicy: nested
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.explicit,
          );
        }
        if (!current()) return PlacementResult.cancelled;
        if (topInset > 0) {
          // ensureVisible may jump immediately; measure after that layout.
          await WidgetsBinding.instance.endOfFrame;
          if (!current()) return PlacementResult.cancelled;
          final viewport = key.currentContext?.findRenderObject() as RenderBox?;
          final row = rows[id]?.currentContext?.findRenderObject() as RenderBox?;
          if (viewport != null &&
              row != null &&
              viewport.attached &&
              row.attached) {
            final covered =
                viewport.localToGlobal(Offset.zero).dy +
                topInset -
                row.localToGlobal(Offset.zero).dy;
            if (covered > 0) {
              scroll.jumpTo(
                (scroll.offset - covered).clamp(
                  0.0,
                  scroll.position.maxScrollExtent,
                ),
              );
            }
          }
        }
        if (delta != 0) {
          scroll.jumpTo(
            (scroll.offset + (building ? -delta : delta)).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
        return PlacementResult.located;
      }
      if (scroll.offset >= scroll.position.maxScrollExtent) {
        return PlacementResult.notLocated;
      }
      scroll.jumpTo(
        (scroll.offset + scroll.position.viewportDimension * .8).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        ),
      );
    }
    return PlacementResult.notLocated;
  }

  /// Keep the visible row at the same screen coordinate after prepending a page.
  Future<void> restoreAnchor({
    required int token,
    required ScrollController scroll,
    required ({String id, double delta}) anchor,
    required bool Function() valid,
    required bool building,
  }) async {
    final result = await locate(
      token: token,
      scroll: scroll,
      id: anchor.id,
      valid: valid,
      building: building,
      firstFloor: false,
      nested: false,
    );
    if (result != PlacementResult.located) return;
    // Slivers may correct their estimated extent on the next layout as the
    // newly inserted rows become measurable.
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!isCurrent(token) || !valid() || !scroll.hasClients) return;
      final viewport = key.currentContext?.findRenderObject() as RenderBox?;
      final row =
          rows[anchor.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (viewport == null ||
          row == null ||
          !viewport.attached ||
          !row.attached)
        return;
      final y =
          row.localToGlobal(Offset.zero).dy -
          viewport.localToGlobal(Offset.zero).dy;
      final shift = y + anchor.delta;
      if (shift.abs() < .5) return;
      scroll.jumpTo(
        (scroll.offset + (building ? -shift : shift)).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        ),
      );
    }
  }
}
