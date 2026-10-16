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
    return showSnackBar(message);
  }
}
