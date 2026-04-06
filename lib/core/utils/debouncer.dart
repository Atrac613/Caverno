import 'dart:async';

import 'package:flutter/foundation.dart';

/// A simple debounce helper that delays action execution until
/// a specified duration has elapsed since the last call.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 500)});

  final Duration duration;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
