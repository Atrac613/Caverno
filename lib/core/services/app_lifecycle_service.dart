import 'package:flutter/widgets.dart';

/// Tracks whether the app is in the background via [WidgetsBindingObserver].
///
/// Only [AppLifecycleState.paused] is considered "background" to avoid false
/// positives during transient states like the app switcher or Control Center.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isInBackground = false;

  bool get isInBackground => _isInBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground = state == AppLifecycleState.paused;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
