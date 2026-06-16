import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Tracks whether the app is in the background via [WidgetsBindingObserver].
///
/// Mobile only treats [AppLifecycleState.paused] as background to avoid false
/// positives during transient states like the app switcher or Control Center.
/// macOS also treats inactive and hidden states as background because users can
/// leave the app running while another app has focus or the window is hidden.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService({DateTime Function() clock = DateTime.now})
    : _clock = clock {
    WidgetsBinding.instance.addObserver(this);
  }

  final DateTime Function() _clock;

  bool _isInBackground = false;
  DateTime? _backgroundSince;

  bool get isInBackground => _isInBackground;

  /// When the app most recently entered the background, or `null` while it is
  /// foregrounded. The LL18 idle-maintenance gate derives idle duration from
  /// this (the app being backgrounded is the idle signal).
  DateTime? get backgroundSince => _backgroundSince;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inBackground =
        state == AppLifecycleState.paused ||
        (Platform.isMacOS &&
            (state == AppLifecycleState.inactive ||
                state == AppLifecycleState.hidden));
    if (inBackground && !_isInBackground) {
      _backgroundSince = _clock();
    } else if (!inBackground) {
      _backgroundSince = null;
    }
    _isInBackground = inBackground;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
