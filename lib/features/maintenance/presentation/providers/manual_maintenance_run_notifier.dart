import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/idle_maintenance_scheduler.dart'
    show IdleMaintenanceRunHandle;
import '../../domain/services/maintenance_pipeline.dart';
import '../../domain/services/maintenance_report_formatter.dart';
import 'maintenance_scheduler_provider.dart';

/// Transient state for a manual (debug) maintenance run. Unlike the scheduled
/// run, a manual run ignores the idle/power/window gate so it can be triggered
/// and inspected on demand.
class ManualMaintenanceRunState {
  const ManualMaintenanceRunState({
    this.isRunning = false,
    this.stageResults = const [],
    this.report,
    this.formatted,
    this.error,
  });

  final bool isRunning;

  /// Per-stage results, accumulated live as each stage finishes.
  final List<MaintenanceStageResult> stageResults;

  /// The completed run report, set once the pipeline finishes.
  final MaintenanceRunReport? report;

  /// The formatted morning report (title + markdown body) for the completed run.
  final FormattedMaintenanceReport? formatted;

  final String? error;

  static const initial = ManualMaintenanceRunState();

  ManualMaintenanceRunState copyWith({
    bool? isRunning,
    List<MaintenanceStageResult>? stageResults,
    MaintenanceRunReport? report,
    FormattedMaintenanceReport? formatted,
    String? error,
    bool clearError = false,
  }) {
    return ManualMaintenanceRunState(
      isRunning: isRunning ?? this.isRunning,
      stageResults: stageResults ?? this.stageResults,
      report: report ?? this.report,
      formatted: formatted ?? this.formatted,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final manualMaintenanceRunNotifierProvider =
    NotifierProvider<ManualMaintenanceRunNotifier, ManualMaintenanceRunState>(
      ManualMaintenanceRunNotifier.new,
    );

/// LL18 debug aid: runs the full maintenance pipeline immediately, bypassing
/// the idle gate, and exposes live per-stage progress plus the final report so
/// the user can manually trigger and inspect an overnight maintenance run.
class ManualMaintenanceRunNotifier extends Notifier<ManualMaintenanceRunState> {
  IdleMaintenanceRunHandle? _activeHandle;

  @override
  ManualMaintenanceRunState build() => ManualMaintenanceRunState.initial;

  /// Runs every configured stage now. Re-entrant calls while a run is in
  /// progress are ignored. The gate is intentionally not consulted.
  Future<void> runNow() async {
    if (state.isRunning) {
      return;
    }
    final pipeline = ref.read(maintenancePipelineProvider);
    final formatter = ref.read(maintenanceReportFormatterProvider);
    final handle = IdleMaintenanceRunHandle();
    _activeHandle = handle;
    state = const ManualMaintenanceRunState(isRunning: true);

    try {
      final report = await pipeline.run(
        handle,
        onStageResult: (result) {
          state = state.copyWith(
            stageResults: [...state.stageResults, result],
          );
        },
      );
      state = state.copyWith(
        isRunning: false,
        report: report,
        formatted: formatter.format(report),
      );
    } catch (error) {
      state = state.copyWith(isRunning: false, error: error.toString());
    } finally {
      if (identical(_activeHandle, handle)) {
        _activeHandle = null;
      }
    }
  }

  /// Requests cancellation of the in-progress run. The pipeline observes it at
  /// the next stage boundary and records the remaining stages as cancelled.
  void cancel() => _activeHandle?.cancel();
}

/// The report formatter, exposed as a provider so tests can override it.
final maintenanceReportFormatterProvider =
    Provider<MaintenanceReportFormatter>(
      (ref) => const MaintenanceReportFormatter(),
    );
