import 'package:flutter/material.dart';

/// Transient feedback, including messages that offer an undo action.
class AppSnackBar extends SnackBar {
  const AppSnackBar({super.key, required super.content, super.action})
    : super(duration: const Duration(seconds: 4), persist: false);
}

extension AppFeedback on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    AppSnackBar message,
  ) {
    clearSnackBars();
    removeCurrentSnackBar();
    return showSnackBar(
      SnackBar(
        duration: message.duration,
        persist: false,
        action: message.action,
        content: Builder(
          builder: (context) {
            final accent = Theme.of(context).colorScheme.primary;
            return Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: accent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: message.content),
              ],
            );
          },
        ),
      ),
    );
  }
}
