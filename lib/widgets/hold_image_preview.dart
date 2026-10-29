import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reliable_image.dart';

/// A temporary, uncropped preview owned by the thumbnail being held.
class HoldImagePreview extends StatefulWidget {
  const HoldImagePreview({super.key, required this.urls, required this.child});

  final List<String> urls;
  final Widget child;

  @override
  State<HoldImagePreview> createState() => _HoldImagePreviewState();
}

class _HoldImagePreviewState extends State<HoldImagePreview>
    with WidgetsBindingObserver {
  OverlayEntry? _preview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _show() {
    if (_preview != null) return;
    _preview = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: ColoredBox(
            color: Colors.black87,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox.expand(
                  child: ReliableImage(
                    urls: widget.urls,
                    useCachedPreview: false,
                    fit: BoxFit.contain,
                    fallback: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_preview!);
  }

  void _hide() {
    _preview?.remove();
    _preview?.dispose();
    _preview = null;
  }

  @override
  void didUpdateWidget(covariant HoldImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) _hide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide();
  }

  @override
  void deactivate() {
    _hide();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: (_) => _show(),
    onLongPressEnd: (_) => _hide(),
    onLongPressCancel: _hide,
    child: widget.child,
  );
}
