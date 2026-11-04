import 'package:flutter/material.dart';

class TopRefreshOverlay extends StatelessWidget {
  const TopRefreshOverlay({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      if (refreshing)
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Material(
                elevation: 3,
                shape: const CircleBorder(),
                color: Theme.of(context).colorScheme.surface,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
