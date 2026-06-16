import 'dart:async';

import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/presentation/providers/manual_maintenance_run_notifier.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stage implements MaintenanceStage {
  _Stage(this.name, this.body);

  @override
  final String name;
  final Future<MaintenanceStageOutcome> Function(MaintenanceStageContext) body;

  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) =>
      body(context);
}

void main() {
  test('runs the pipeline bypassing the gate and exposes the report', () async {
    final container = ProviderContainer(
      overrides: [
        maintenanceStagesProvider.overrideWithValue([
          _Stage('probe', (_) async {
            return const MaintenanceStageOutcome.completed('profiled');
          }),
          _Stage('eval', (_) async {
            return const MaintenanceStageOutcome.skipped('no cases');
          }),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      manualMaintenanceRunNotifierProvider.notifier,
    );
    await notifier.runNow();

    final state = container.read(manualMaintenanceRunNotifierProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isNull);
    expect(state.stageResults.map((s) => s.name), ['probe', 'eval']);
    expect(state.report, isNotNull);
    expect(state.report!.completedCount, 1);
    expect(state.report!.skippedCount, 1);
    expect(state.formatted, isNotNull);
    expect(state.formatted!.title, contains('1 done'));
    expect(state.formatted!.body, contains('| probe |'));
  });

  test('accumulates stage results live as the pipeline progresses', () async {
    final gate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        maintenanceStagesProvider.overrideWithValue([
          _Stage('probe', (_) async {
            return const MaintenanceStageOutcome.completed();
          }),
          _Stage('calibrate', (_) async {
            await gate.future; // hold here so we can observe partial progress
            return const MaintenanceStageOutcome.completed();
          }),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      manualMaintenanceRunNotifierProvider.notifier,
    );
    final run = notifier.runNow();

    // Let the first stage complete and the second stage start awaiting.
    await Future<void>.delayed(Duration.zero);
    final midState = container.read(manualMaintenanceRunNotifierProvider);
    expect(midState.isRunning, isTrue);
    expect(midState.stageResults.map((s) => s.name), ['probe']);

    gate.complete();
    await run;

    final finalState = container.read(manualMaintenanceRunNotifierProvider);
    expect(finalState.isRunning, isFalse);
    expect(finalState.stageResults.map((s) => s.name), ['probe', 'calibrate']);
  });

  test('cancel stops the remaining stages', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        maintenanceStagesProvider.overrideWithValue([
          _Stage('probe', (_) async {
            started.complete();
            await release.future;
            return const MaintenanceStageOutcome.completed();
          }),
          _Stage('eval', (_) async {
            return const MaintenanceStageOutcome.completed();
          }),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      manualMaintenanceRunNotifierProvider.notifier,
    );
    final run = notifier.runNow();

    await started.future;
    notifier.cancel();
    release.complete();
    await run;

    final state = container.read(manualMaintenanceRunNotifierProvider);
    expect(state.isRunning, isFalse);
    expect(state.report!.cancelledCount, 1);
    expect(
      state.report!.stages.last.status,
      MaintenanceStageStatus.cancelled,
    );
  });

  test('a concurrent runNow call is ignored while a run is in progress', () async {
    final release = Completer<void>();
    var probeRuns = 0;
    final container = ProviderContainer(
      overrides: [
        maintenanceStagesProvider.overrideWithValue([
          _Stage('probe', (_) async {
            probeRuns++;
            await release.future;
            return const MaintenanceStageOutcome.completed();
          }),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      manualMaintenanceRunNotifierProvider.notifier,
    );
    final first = notifier.runNow();
    await Future<void>.delayed(Duration.zero);
    await notifier.runNow(); // should be a no-op while the first run is active

    release.complete();
    await first;

    expect(probeRuns, 1);
  });
}
