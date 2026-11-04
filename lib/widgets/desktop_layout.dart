import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop-only layout and input helpers. On phones and tablets every widget
/// here returns its child unchanged.

/// Whether the app runs as the Windows desktop build.
bool get isDesktop => defaultTargetPlatform == TargetPlatform.windows;

/// Width of the reading column (thread text, settings and other list pages).
const desktopColumnWidth = 760.0;

/// Widest the multi-column feed grows before leaving margins at the sides.
const desktopFeedWidth = 1480.0;

/// Centers a whole page (app bar included) in a [desktopColumnWidth] column.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({
    super.key,
    required this.child,
    this.maxWidth = desktopColumnWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (context, box) => Center(
          child: SizedBox(
            width: math.min(box.maxWidth, maxWidth),
            height: box.maxHeight,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Horizontal margin that keeps content of [maxWidth] centered in [available].
double desktopGutter(double available, double maxWidth) =>
    isDesktop ? math.max(0, (available - maxWidth) / 2) : 0;

/// Card background for feed entries on desktop, slightly lifted from the page.
Color desktopCardColor(ThemeData theme) => Color.alphaBlend(
  Colors.white.withValues(
    alpha: theme.brightness == Brightness.dark ? .05 : .65,
  ),
  theme.scaffoldBackgroundColor,
);

/// Tracks whether the mouse is over a feed card, for controls shown on hover.
class DesktopHoverRegion extends StatefulWidget {
  const DesktopHoverRegion({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopHoverRegion> createState() => _DesktopHoverRegionState();
}

class _DesktopHoverRegionState extends State<DesktopHoverRegion> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hovered.value = true,
    onExit: (_) => _hovered.value = false,
    child: _HoverScope(notifier: _hovered, child: widget.child),
  );
}

class _HoverScope extends InheritedNotifier<ValueNotifier<bool>> {
  const _HoverScope({required super.notifier, required super.child});
}

/// On desktop, shows [child] only while the enclosing [DesktopHoverRegion] is
/// hovered or the child has keyboard focus. Elsewhere it is always visible.
class ShowOnHover extends StatefulWidget {
  const ShowOnHover({super.key, required this.child});
  final Widget child;

  @override
  State<ShowOnHover> createState() => _ShowOnHoverState();
}

class _ShowOnHoverState extends State<ShowOnHover> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HoverScope>();
    if (!isDesktop || scope == null) return widget.child;
    final visible = scope.notifier!.value || _focused;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Registers [onRefresh] as this page's F5 action. F5 refreshes the page on
/// top of the navigator, wherever the keyboard focus is.
class DesktopRefreshShortcut extends StatefulWidget {
  const DesktopRefreshShortcut({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final VoidCallback onRefresh;
  final Widget child;

  @override
  State<DesktopRefreshShortcut> createState() => _DesktopRefreshShortcutState();
}

class _DesktopRefreshShortcutState extends State<DesktopRefreshShortcut> {
  static final _registered = <_DesktopRefreshShortcutState>[];

  /// Refreshes the page on top, if it registered a refresh action.
  static bool refreshCurrent() {
    for (final state in _registered.reversed) {
      if (state.mounted && (ModalRoute.of(state.context)?.isCurrent ?? true)) {
        state.widget.onRefresh();
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _registered.add(this);
  }

  @override
  void dispose() {
    _registered.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// App-wide desktop input: Esc and the mouse "back" button go back a page,
/// F5 refreshes the current page.
///
/// Dialogs, menus and sheets keep Flutter's own Esc handling, so a dialog that
/// must be answered is not closed by Esc.
class DesktopNavigationInput extends StatelessWidget {
  const DesktopNavigationInput({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) {
          navigatorKey.currentState?.maybePop();
        }
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
          SingleActivator(LogicalKeyboardKey.f5): _RefreshIntent(),
        },
        child: Actions(
          actions: {
            _BackIntent: _BackAction(navigatorKey),
            _RefreshIntent: CallbackAction<_RefreshIntent>(
              onInvoke: (_) => _DesktopRefreshShortcutState.refreshCurrent(),
            ),
          },
          child: child,
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _BackAction extends Action<_BackIntent> {
  _BackAction(this.navigatorKey);
  final GlobalKey<NavigatorState> navigatorKey;

  static bool _inTextField(FocusNode? focus) {
    final context = focus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  @override
  bool isEnabled(_BackIntent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    // Leave Esc to the open dialog, menu or sheet.
    return context == null || ModalRoute.of(context) is! PopupRoute;
  }

  @override
  Object? invoke(_BackIntent intent) {
    final focus = FocusManager.instance.primaryFocus;
    // In a text box, Esc only leaves the box; a second Esc goes back.
    if (_inTextField(focus)) {
      focus!.unfocus();
    } else {
      navigatorKey.currentState?.maybePop();
    }
    return null;
  }
}
