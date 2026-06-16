import 'idle_maintenance_scheduler.dart' show IdleMaintenanceRunHandle;

/// Terminal status of one maintenance stage.
enum MaintenanceStageStatus {
  /// The stage ran and did its work.
  completed,

  /// The stage ran but had nothing to do (a precondition was not met).
  skipped,

  /// The stage threw; its error is captured and the run continues so the
  /// report stays complete.
  failed,

  /// The stage did not run because the gate closed mid-run (the user returned,
  /// power dropped, the window ended) or [stop] was called.
  cancelled,
}

/// What a [MaintenanceStage] reports back: completed or skipped, with an
/// optional human-readable detail. Failures are signalled by throwing.
class MaintenanceStageOutcome {
  const MaintenanceStageOutcome._(this.status, this.detail);

  const MaintenanceStageOutcome.completed([String? detail])
    : this._(MaintenanceStageStatus.completed, detail);

  const MaintenanceStageOutcome.skipped([String? detail])
    : this._(MaintenanceStageStatus.skipped, detail);

  final MaintenanceStageStatus status;
  final String? detail;
}

/// Shared context handed to each stage: the cancellation handle, a clock, and a
/// mutable bag so a stage can pass evidence to a later one (e.g. the eval stage
/// records its verdict for the adopt stage to gate on).
class MaintenanceStageContext {
  MaintenanceStageContext({
    required this.handle,
    required this.shared,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  final IdleMaintenanceRunHandle handle;
  final Map<String, Object?> shared;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  /// Long stages must poll this and stop promptly when it becomes true.
  bool get isCancelled => handle.isCancelled;
}

/// One unit of maintenance work (probe, calibrate, eval, mine, adopt, ...).
/// Return an outcome; throw to fail. The concrete service-backed stages are
/// wired in later slices.
abstract interface class MaintenanceStage {
  String get name;

  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context);
}

/// Per-stage entry in the run report.
class MaintenanceStageResult {
  const MaintenanceStageResult({
    required this.name,
    required this.status,
    this.detail,
    this.duration = Duration.zero,
  });

  final String name;
  final MaintenanceStageStatus status;
  final String? detail;
  final Duration duration;
}

/// The structured outcome of a maintenance run. The morning report (a later
/// slice) formats and delivers this; it is produced even when nothing was
/// adopted or the run was cancelled.
class MaintenanceRunReport {
  const MaintenanceRunReport({
    required this.startedAt,
    required this.finishedAt,
    required this.stages,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final List<MaintenanceStageResult> stages;

  Duration get duration => finishedAt.difference(startedAt);

  int _count(MaintenanceStageStatus status) =>
      stages.where((stage) => stage.status == status).length;

  int get completedCount => _count(MaintenanceStageStatus.completed);
  int get skippedCount => _count(MaintenanceStageStatus.skipped);
  int get failedCount => _count(MaintenanceStageStatus.failed);
  int get cancelledCount => _count(MaintenanceStageStatus.cancelled);

  bool get wasCancelled => cancelledCount > 0;
  bool get hadFailures => failedCount > 0;
}

/// LL18 maintenance pipeline: runs a configured list of [MaintenanceStage]s in
/// order, capturing each stage's result so the run is atomic per stage — a
/// stage failure is recorded and the run continues, never corrupting later
/// stages, and the report is always complete.
///
/// Cancellation is honored at every stage boundary: once the run handle is
/// cancelled the remaining stages are recorded as cancelled and never executed,
/// so a returning user stops further work promptly.
class MaintenancePipeline {
  MaintenancePipeline({
    required this.stages,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  final List<MaintenanceStage> stages;
  final DateTime Function() _clock;

  /// Runs the configured stages in order.
  ///
  /// [onStageResult] is invoked with each stage's result as soon as it is
  /// recorded (completed/skipped/failed/cancelled). It lets a debug UI render
  /// live per-stage progress without changing how the scheduler consumes the
  /// final report; the scheduler omits it.
  Future<MaintenanceRunReport> run(
    IdleMaintenanceRunHandle handle, {
    void Function(MaintenanceStageResult result)? onStageResult,
  }) async {
    final startedAt = _clock();
    final context = MaintenanceStageContext(
      handle: handle,
      shared: <String, Object?>{},
      clock: _clock,
    );
    final results = <MaintenanceStageResult>[];
    var stopped = false;

    void record(MaintenanceStageResult result) {
      results.add(result);
      onStageResult?.call(result);
    }

    for (final stage in stages) {
      if (stopped || handle.isCancelled) {
        record(
          MaintenanceStageResult(
            name: stage.name,
            status: MaintenanceStageStatus.cancelled,
          ),
        );
        stopped = true;
        continue;
      }

      final stageStart = _clock();
      try {
        final outcome = await stage.run(context);
        record(
          MaintenanceStageResult(
            name: stage.name,
            status: outcome.status,
            detail: outcome.detail,
            duration: _clock().difference(stageStart),
          ),
        );
      } catch (error) {
        record(
          MaintenanceStageResult(
            name: stage.name,
            status: MaintenanceStageStatus.failed,
            detail: error.toString(),
            duration: _clock().difference(stageStart),
          ),
        );
      }

      // If the gate closed while the stage ran, stop before the next one.
      if (handle.isCancelled) {
        stopped = true;
      }
    }

    return MaintenanceRunReport(
      startedAt: startedAt,
      finishedAt: _clock(),
      stages: results,
    );
  }
}
