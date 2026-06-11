import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Tracks whether the app is in the background via [WidgetsBindingObserver].
///
/// Mobile only treats [AppLifecycleState.paused] as background to avoid false
/// positives during transient states like the app switcher or Control Center.
/// macOS also treats inactive and hidden states as background because users can
/// leave the app running while another app has focus or the window is hidden.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isInBackground = false;

  bool get isInBackground => _isInBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground =
        state == AppLifecycleState.paused ||
        (Platform.isMacOS &&
            (state == AppLifecycleState.inactive ||
                state == AppLifecycleState.hidden));
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
