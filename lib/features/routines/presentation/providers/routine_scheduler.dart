import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routines_notifier.dart';

final routineSchedulerProvider = Provider<RoutineSchedulerController>((ref) {
  final controller = RoutineSchedulerController(ref);
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

class RoutineSchedulerController with WidgetsBindingObserver {
  RoutineSchedulerController(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _started = false;
  bool _isChecking = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkDueRoutines();
    });
    Future<void>.microtask(_checkDueRoutines);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDueRoutines();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkDueRoutines() async {
    if (_isChecking || !_ref.mounted) {
      return;
    }

    _isChecking = true;
    try {
      await _ref.read(routinesNotifierProvider.notifier).runDueRoutines();
    } finally {
      _isChecking = false;
    }
  }
}
