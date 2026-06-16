import 'dart:async';

import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEnvironment implements IdleMaintenanceEnvironment {
  _FakeEnvironment({required this.nowValue, this.acPower = true});

  DateTime nowValue;
  Duration idle = const Duration(hours: 1);
  bool? acPower;

  @override
  DateTime now() => nowValue;

  @override
  Duration idleFor() => idle;

  @override
  bool? onAcPower() => acPower;
}

/// A run the test can hold open (awaiting [gate]) so it can assert behavior
/// while a run is in progress.
class _ControllableRun {
  int startCount = 0;
  IdleMaintenanceRunHandle? lastHandle;
  Completer<void> gate = Completer<void>();

  Future<void> call(IdleMaintenanceRunHandle handle) async {
    startCount++;
    lastHandle = handle;
    await gate.future;
  }

  void finish() {
    if (!gate.isCompleted) gate.complete();
    gate = Completer<void>();
  }
}

void main() {
  // Enabled, 02:00-06:00, 10 min idle, AC required.
  const config = IdleMaintenanceConfig(
    enabled: true,
    windowStartMinutes: 120,
    windowEndMinutes: 360,
    minIdle: Duration(minutes: 10),
    requireAcPower: true,
  );

  DateTime at(int hour, int minute) => DateTime(2026, 6, 16, hour, minute);

  IdleMaintenanceScheduler buildScheduler(
    _FakeEnvironment env,
    _ControllableRun run,
  ) {
    return IdleMaintenanceScheduler(
      environment: env,
      configProvider: () => config,
      run: run.call,
    );
  }

  test('starts a run on the blocked->allowed rising edge', () async {
    final env = _FakeEnvironment(nowValue: at(12, 0)); // outside window
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick();
    expect(run.startCount, 0, reason: 'blocked gate must not run');

    env.nowValue = at(3, 0); // inside window
    await scheduler.tick();
    expect(run.startCount, 1);
    expect(scheduler.isRunning, isTrue);

    run.finish();
    await scheduler.drain();
    expect(scheduler.isRunning, isFalse);
  });

  test('does not start a second run while the gate stays open', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0));
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick(); // rising edge -> run 1
    expect(run.startCount, 1);
    run.finish();
    await scheduler.drain();

    // Gate still open: no new run without a fresh rising edge.
    await scheduler.tick();
    await scheduler.tick();
    expect(run.startCount, 1);
  });

  test('cancels the in-progress run when the gate closes', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0));
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick(); // run starts, held open
    expect(run.lastHandle!.isCancelled, isFalse);

    env.nowValue = at(
      12,
      0,
    ); // user effectively "returns": window/idle gate closes
    await scheduler.tick();
    expect(run.lastHandle!.isCancelled, isTrue);

    run.finish();
    await scheduler.drain();
  });

  test('cancels the in-progress run when power drops mid-run', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0), acPower: true);
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick();
    expect(run.lastHandle!.isCancelled, isFalse);

    env.acPower = false; // unplugged
    await scheduler.tick();
    expect(run.lastHandle!.isCancelled, isTrue);

    run.finish();
    await scheduler.drain();
  });

  test('stop cancels the active run and halts polling', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0));
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick();
    expect(scheduler.isRunning, isTrue);

    scheduler.stop();
    expect(run.lastHandle!.isCancelled, isTrue);

    run.finish();
    await scheduler.drain();
    expect(scheduler.isRunning, isFalse);
  });

  test('runs again after the gate closes and reopens', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0));
    final run = _ControllableRun();
    final scheduler = buildScheduler(env, run);

    await scheduler.tick(); // run 1
    run.finish();
    await scheduler.drain();
    expect(run.startCount, 1);

    env.nowValue = at(12, 0); // close
    await scheduler.tick();

    env.nowValue = at(3, 0); // reopen -> rising edge
    await scheduler.tick();
    expect(run.startCount, 2);

    run.finish();
    await scheduler.drain();
  });

  test('never runs while the gate is disabled', () async {
    final env = _FakeEnvironment(nowValue: at(3, 0));
    final run = _ControllableRun();
    final scheduler = IdleMaintenanceScheduler(
      environment: env,
      configProvider: () => config.copyWith(enabled: false),
      run: run.call,
    );

    await scheduler.tick();
    await scheduler.tick();
    expect(run.startCount, 0);
  });
}
