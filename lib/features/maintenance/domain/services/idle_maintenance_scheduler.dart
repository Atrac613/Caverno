import 'dart:async';

import '../entities/idle_maintenance_config.dart';
import 'idle_maintenance_environment.dart';
import 'idle_maintenance_window_policy.dart';

/// Handle passed to a maintenance run so it can check, between stages, whether
/// it should keep going. The scheduler cancels it when the gate closes (the
/// user returned, power dropped, the window ended) or when [stop] is called.
class IdleMaintenanceRunHandle {
  bool _cancelled = false;

  /// Whether the run should abort at the next stage boundary.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. The scheduler calls this when the gate closes; the
  /// run observes [isCancelled] at its next stage boundary and unwinds.
  void cancel() => _cancelled = true;
}

/// The work performed when the gate opens. The real maintenance pipeline
/// (probe -> calibrate -> eval -> mine -> adopt -> report) is injected here in
/// a later slice; the run must poll [IdleMaintenanceRunHandle.isCancelled]
/// between stages and stop promptly when cancelled.
typedef IdleMaintenanceRun =
    Future<void> Function(IdleMaintenanceRunHandle handle);

/// LL18 scheduler skeleton: polls the gate, starts a maintenance run when the
/// gate opens, re-checks the gate while a run is in progress and cancels it the
/// moment the gate closes, and is fully cancelable.
///
/// Edge-triggered: a run starts only on the transition into "allowed", so a
/// completed run is not immediately restarted while the gate stays open. The
/// clock, idle, and power inputs come from an injected
/// [IdleMaintenanceEnvironment], and ticks can be driven manually in tests, so
/// the whole control loop is deterministic without real timers or platform
/// probing.
class IdleMaintenanceScheduler {
  IdleMaintenanceScheduler({
    required IdleMaintenanceEnvironment environment,
    required IdleMaintenanceConfig Function() configProvider,
    required IdleMaintenanceRun run,
    IdleMaintenanceWindowPolicy policy = const IdleMaintenanceWindowPolicy(),
  }) : _environment = environment,
       _configProvider = configProvider,
       _run = run,
       _policy = policy;

  final IdleMaintenanceEnvironment _environment;
  final IdleMaintenanceConfig Function() _configProvider;
  final IdleMaintenanceRun _run;
  final IdleMaintenanceWindowPolicy _policy;

  Timer? _timer;
  IdleMaintenanceRunHandle? _activeHandle;
  Future<void>? _activeRun;
  bool _allowedLastTick = false;

  /// Whether a maintenance run is currently in progress.
  bool get isRunning => _activeHandle != null;

  /// Begins periodic polling. Each period evaluates the gate via [tick].
  void start({Duration interval = const Duration(minutes: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// Evaluates the gate once and reconciles the run state. Public so tests can
  /// drive the control loop deterministically without a real timer.
  Future<void> tick() async {
    final allowed = _evaluateAllowed();

    if (_activeHandle != null) {
      // A run is in progress: cancel it the moment the gate closes.
      if (!allowed) {
        _activeHandle!.cancel();
      }
      _allowedLastTick = allowed;
      return;
    }

    // Rising edge only: start a run when the gate transitions blocked->allowed.
    if (allowed && !_allowedLastTick) {
      _startRun();
    }
    _allowedLastTick = allowed;
  }

  bool _evaluateAllowed() {
    return _policy
        .evaluate(
          config: _configProvider(),
          now: _environment.now(),
          idleFor: _environment.idleFor(),
          onAcPower: _environment.onAcPower(),
        )
        .allowed;
  }

  void _startRun() {
    final handle = IdleMaintenanceRunHandle();
    _activeHandle = handle;
    _activeRun = _run(handle).whenComplete(() {
      if (identical(_activeHandle, handle)) {
        _activeHandle = null;
        _activeRun = null;
      }
    });
  }

  /// Cancels any in-progress run (via its handle) and stops polling. The run is
  /// expected to observe the cancellation at its next stage boundary; callers
  /// can await [drain] to wait for it to unwind.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _activeHandle?.cancel();
    _allowedLastTick = false;
  }

  /// Awaits the in-progress run, if any, so callers (and tests) can wait for a
  /// cancelled run to finish unwinding.
  Future<void> drain() async {
    await _activeRun;
  }

  /// Stops the scheduler and drains the active run.
  Future<void> dispose() async {
    stop();
    await drain();
  }
}
