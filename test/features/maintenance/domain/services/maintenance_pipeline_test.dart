import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A configurable stage: its [body] receives the context and returns an
/// outcome (or throws to fail).
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
  test('runs every stage in order and aggregates the report', () async {
    final order = <String>[];
    final pipeline = MaintenancePipeline(
      stages: [
        _Stage('probe', (_) async {
          order.add('probe');
          return const MaintenanceStageOutcome.completed('profiled');
        }),
        _Stage('calibrate', (_) async {
          order.add('calibrate');
          return const MaintenanceStageOutcome.skipped('nothing to tune');
        }),
      ],
    );

    final report = await pipeline.run(IdleMaintenanceRunHandle());

    expect(order, ['probe', 'calibrate']);
    expect(report.stages.map((s) => s.name), ['probe', 'calibrate']);
    expect(report.completedCount, 1);
    expect(report.skippedCount, 1);
    expect(report.failedCount, 0);
    expect(report.wasCancelled, isFalse);
    expect(report.stages.first.detail, 'profiled');
  });

  test('captures a failing stage and continues the run', () async {
    final ran = <String>[];
    final pipeline = MaintenancePipeline(
      stages: [
        _Stage('probe', (_) async {
          ran.add('probe');
          throw StateError('endpoint down');
        }),
        _Stage('eval', (_) async {
          ran.add('eval');
          return const MaintenanceStageOutcome.completed();
        }),
      ],
    );

    final report = await pipeline.run(IdleMaintenanceRunHandle());

    expect(ran, ['probe', 'eval'], reason: 'a failure must not abort the run');
    expect(report.failedCount, 1);
    expect(report.hadFailures, isTrue);
    expect(report.stages.first.status, MaintenanceStageStatus.failed);
    expect(report.stages.first.detail, contains('endpoint down'));
    expect(report.completedCount, 1);
  });

  test('passes shared context from one stage to the next', () async {
    final pipeline = MaintenancePipeline(
      stages: [
        _Stage('eval', (ctx) async {
          ctx.shared['candidateReady'] = true;
          return const MaintenanceStageOutcome.completed();
        }),
        _Stage('adopt', (ctx) async {
          final ready = ctx.shared['candidateReady'] == true;
          return ready
              ? const MaintenanceStageOutcome.completed('adopted')
              : const MaintenanceStageOutcome.skipped('gate not passed');
        }),
      ],
    );

    final report = await pipeline.run(IdleMaintenanceRunHandle());
    expect(report.stages.last.status, MaintenanceStageStatus.completed);
    expect(report.stages.last.detail, 'adopted');
  });

  test(
    'a cancelled handle marks all stages cancelled without running',
    () async {
      final ran = <String>[];
      final handle = IdleMaintenanceRunHandle()..cancel();
      final pipeline = MaintenancePipeline(
        stages: [
          _Stage('probe', (_) async {
            ran.add('probe');
            return const MaintenanceStageOutcome.completed();
          }),
          _Stage('eval', (_) async {
            ran.add('eval');
            return const MaintenanceStageOutcome.completed();
          }),
        ],
      );

      final report = await pipeline.run(handle);

      expect(ran, isEmpty);
      expect(report.cancelledCount, 2);
      expect(report.wasCancelled, isTrue);
      expect(
        report.stages.every(
          (s) => s.status == MaintenanceStageStatus.cancelled,
        ),
        isTrue,
      );
    },
  );

  test('cancelling mid-run stops the remaining stages', () async {
    final ran = <String>[];
    final handle = IdleMaintenanceRunHandle();
    final pipeline = MaintenancePipeline(
      stages: [
        _Stage('probe', (ctx) async {
          ran.add('probe');
          // The gate closes (user returns) while this stage runs.
          ctx.handle.cancel();
          return const MaintenanceStageOutcome.completed();
        }),
        _Stage('calibrate', (_) async {
          ran.add('calibrate');
          return const MaintenanceStageOutcome.completed();
        }),
        _Stage('eval', (_) async {
          ran.add('eval');
          return const MaintenanceStageOutcome.completed();
        }),
      ],
    );

    final report = await pipeline.run(handle);

    expect(ran, ['probe'], reason: 'stages after cancellation must not run');
    expect(report.stages[0].status, MaintenanceStageStatus.completed);
    expect(report.stages[1].status, MaintenanceStageStatus.cancelled);
    expect(report.stages[2].status, MaintenanceStageStatus.cancelled);
  });

  test('an empty pipeline produces an empty report', () async {
    final report = await MaintenancePipeline(
      stages: const [],
    ).run(IdleMaintenanceRunHandle());
    expect(report.stages, isEmpty);
    expect(report.wasCancelled, isFalse);
    expect(report.hadFailures, isFalse);
  });

  test('onStageResult fires live for each stage, including cancelled', () async {
    final handle = IdleMaintenanceRunHandle();
    final pipeline = MaintenancePipeline(
      stages: [
        _Stage('probe', (_) async {
          return const MaintenanceStageOutcome.completed('ok');
        }),
        _Stage('calibrate', (_) async {
          // Gate closes during this stage; the next stage must be cancelled.
          handle.cancel();
          return const MaintenanceStageOutcome.completed();
        }),
        _Stage('eval', (_) async {
          return const MaintenanceStageOutcome.completed();
        }),
      ],
    );

    final observed = <String>[];
    final report = await pipeline.run(
      handle,
      onStageResult: (result) =>
          observed.add('${result.name}:${result.status.name}'),
    );

    // The callback observes results in order, one per stage, matching the
    // final report exactly.
    expect(observed, [
      'probe:completed',
      'calibrate:completed',
      'eval:cancelled',
    ]);
    expect(
      report.stages.map((s) => '${s.name}:${s.status.name}'),
      observed,
    );
  });
}
