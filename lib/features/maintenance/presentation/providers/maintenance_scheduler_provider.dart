import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/live_llm_diagnostic_notifier.dart';
import '../../../settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/model_edit_failure_trace_extractor.dart';
import '../../domain/services/callback_maintenance_stage.dart';
import '../../domain/services/failure_trace_miner.dart';
import '../../domain/services/harness_proposal_service.dart';
import '../../domain/services/idle_maintenance_scheduler.dart';
import '../../domain/services/maintenance_pipeline.dart';
import 'idle_maintenance_config_provider.dart';
import 'idle_maintenance_environment_provider.dart';
import 'maintenance_report_service_provider.dart';

/// Shared-context key the propose stage sets with the [HarnessConfigProposal]
/// the adopt stage should consider. Absent when nothing was proposed.
const maintenanceProposedCandidateKey = 'maintenance.proposedCandidate';

/// Shared-context key the mine stage sets with the top [FailureCluster] for the
/// propose stage to turn into a candidate edit.
const maintenanceTopClusterKey = 'maintenance.topCluster';

/// Supplies recorded failure traces to the LL17 mine stage. Extracts the active
/// model's LL15 edit-apply failure-kind counters; empty when the model has no
/// capability profile yet. Override in tests to feed synthetic traces.
final maintenanceFailureTraceSourceProvider =
    Provider<Future<List<FailureTrace>> Function()>((ref) {
      return () async {
        final settings = ref.read(settingsNotifierProvider);
        final profile = settings.effectiveModelCapabilityProfile;
        if (profile == null) {
          return const <FailureTrace>[];
        }
        return const ModelEditFailureTraceExtractor().extract(
          caseId: settings.effectiveModel,
          profileMetadata: profile.probeMetadata,
        );
      };
    });

/// The ordered maintenance stages run on each idle window:
/// probe -> calibrate -> eval -> mine -> propose -> adopt.
///
/// Wired today: re-probe the active model (LL3/LL21), sampler calibration via
/// the full diagnostic (LL16), a baseline eval over the recorded suite (LL19),
/// LL17 weakness mining that clusters failure traces, and an LL17 propose stage
/// that turns the top cluster into one minimal grounded harness edit. Adopt
/// surfaces that edit as a recommendation; auto-applying it on candidate-applied
/// held-in/held-out validation is the remaining LL17 piece.
final maintenanceStagesProvider = Provider<List<MaintenanceStage>>((ref) {
  return [
    CallbackMaintenanceStage(
      name: 'probe',
      body: (_) async {
        await ref
            .read(modelCapabilityAutoProbeNotifierProvider.notifier)
            .runForCurrentModel(force: true);
        return const MaintenanceStageOutcome.completed(
          're-probed active model',
        );
      },
    ),
    CallbackMaintenanceStage(
      name: 'calibrate',
      body: (_) async {
        // The full diagnostic re-measures the model and records LL16 sampler
        // calibration, persisting the updated profile.
        await ref.read(liveLlmDiagnosticNotifierProvider.notifier).run();
        return const MaintenanceStageOutcome.completed(
          'ran diagnostic + sampler calibration',
        );
      },
    ),
    CallbackMaintenanceStage(
      name: 'eval',
      body: (context) async {
        final run = await ref
            .read(personalEvalCasesNotifierProvider.notifier)
            .replayAllCases();
        if (run.caseCount == 0) {
          return const MaintenanceStageOutcome.skipped('no recorded cases');
        }
        context.shared['maintenance.evalNonRegressing'] = run.failedCount == 0;
        return MaintenanceStageOutcome.completed(
          'eval: ${run.passedCount}/${run.caseCount} passed',
        );
      },
    ),
    CallbackMaintenanceStage(
      name: 'mine',
      body: (context) async {
        // LL17 weakness mining: cluster recorded failure traces and hand the
        // top cluster to the propose stage.
        final traces = await ref.read(maintenanceFailureTraceSourceProvider)();
        if (traces.isEmpty) {
          return const MaintenanceStageOutcome.skipped('no failure traces');
        }
        final clusters = const FailureTraceMiner().mine(traces);
        final top = clusters.first;
        context.shared[maintenanceTopClusterKey] = top;
        return MaintenanceStageOutcome.completed(
          'mined ${clusters.length} cluster(s); '
          'top ${top.signature} x${top.support}',
        );
      },
    ),
    CallbackMaintenanceStage(
      name: 'propose',
      body: (context) async {
        // Turn the top mined weakness into one minimal, grounded harness edit.
        final top = context.shared[maintenanceTopClusterKey];
        if (top is! FailureCluster) {
          return const MaintenanceStageOutcome.skipped('no mined weakness');
        }
        final settings = ref.read(settingsNotifierProvider);
        final base =
            settings.effectiveModelHarnessConfig ??
            ModelHarnessConfig(
              id: ModelHarnessConfig.buildId(
                provider: settings.llmProvider,
                baseUrl: settings.baseUrl,
                model: settings.effectiveModel,
              ),
              provider: settings.llmProvider,
              baseUrl: settings.baseUrl,
              model: settings.effectiveModel,
            );
        final proposal = const HarnessProposalService().propose(
          cluster: top,
          base: base,
        );
        if (proposal == null) {
          return MaintenanceStageOutcome.skipped(
            'no harness rule for ${top.signature.mechanism}',
          );
        }
        context.shared[maintenanceProposedCandidateKey] = proposal;
        return MaintenanceStageOutcome.completed(
          'proposed ${proposal.surface} edit for ${proposal.mechanism}',
        );
      },
    ),
    CallbackMaintenanceStage(
      name: 'adopt',
      body: (context) async {
        final proposal = context.shared[maintenanceProposedCandidateKey];
        if (proposal is! HarnessConfigProposal) {
          return const MaintenanceStageOutcome.skipped('no candidate proposed');
        }
        // Auto-applying a harness edit requires candidate-applied
        // held-in/held-out validation (the remaining LL17 piece) and manual
        // review for high-stakes surfaces, so surface a recommendation rather
        // than silently persisting the edit.
        return MaintenanceStageOutcome.completed(
          'recommended harness edit for ${proposal.mechanism}: '
          '${proposal.surface} (manual review)',
        );
      },
    ),
  ];
});

/// The pipeline assembled from the configured stages.
final maintenancePipelineProvider = Provider<MaintenancePipeline>((ref) {
  return MaintenancePipeline(stages: ref.watch(maintenanceStagesProvider));
});

/// LL18: the wired idle-maintenance scheduler. On each gate opening it runs the
/// pipeline and delivers the morning report. Started on desktop from `main`;
/// the gate (config + idle + power) decides whether anything actually runs.
final idleMaintenanceSchedulerProvider = Provider<IdleMaintenanceScheduler>((
  ref,
) {
  final pipeline = ref.watch(maintenancePipelineProvider);
  final reportService = ref.watch(maintenanceReportServiceProvider);

  final scheduler = IdleMaintenanceScheduler(
    environment: ref.watch(idleMaintenanceEnvironmentProvider),
    // Read live each tick so settings changes take effect without a rebuild.
    configProvider: () => ref.read(idleMaintenanceConfigProvider),
    run: (handle) async {
      final report = await pipeline.run(handle);
      // Only notify when stages actually executed, so a run that was
      // immediately cancelled (gate closed) does not bug the user.
      final executed =
          report.completedCount + report.failedCount + report.skippedCount;
      if (executed > 0) {
        await reportService.deliver(report);
      }
    },
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
