import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../chat/data/repositories/worktree_agent_task_repository.dart';
import '../../../chat/data/repositories/retry_until_green_report_repository.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/model_usage_role.dart';
import '../../../chat/domain/services/kv_cache_warmup_service.dart';
import '../../../chat/domain/services/repo_map_precompute_cache.dart';
import '../../../chat/domain/services/system_prompt_builder.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../../chat/presentation/providers/repo_map_precompute_cache_provider.dart';
import '../../../personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import '../../../personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/model_benchmark_history.dart';
import '../../../settings/presentation/providers/live_llm_diagnostic_notifier.dart';
import '../../../settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../../routines/data/routine_repository.dart';
import '../../data/model_edit_failure_trace_extractor.dart';
import '../../domain/services/ll37_objective_verdict_projection_builder.dart';
import '../../domain/services/callback_maintenance_stage.dart';
import '../../domain/services/candidate_adoption_service.dart';
import '../../domain/services/failure_trace_miner.dart';
import '../../domain/services/harness_proposal_service.dart';
import '../../domain/services/idle_maintenance_scheduler.dart';
import '../../domain/services/ll37_objective_verification_panel.dart';
import '../../domain/services/ll37_objective_vote_policy.dart';
import '../../domain/services/ll37_retry_until_green_candidate_adapter.dart';
import '../../domain/services/ll37_routine_candidate_adapter.dart';
import '../../domain/services/ll37_verifier_fidelity_profile.dart';
import '../../domain/services/ll37_worktree_agent_candidate_adapter.dart';
import '../../domain/services/maintenance_pipeline.dart';
import 'idle_maintenance_config_provider.dart';
import 'idle_maintenance_environment_provider.dart';
import 'll37_objective_verdict_history_notifier.dart';
import 'maintenance_report_service_provider.dart';

/// Shared-context key the propose stage sets with the [HarnessConfigProposal]
/// the adopt stage should consider. Absent when nothing was proposed.
const maintenanceProposedCandidateKey = 'maintenance.proposedCandidate';

/// Shared-context key the mine stage sets with the top [FailureCluster] for the
/// propose stage to turn into a candidate edit.
const maintenanceTopClusterKey = 'maintenance.topCluster';

/// Run-local LL37 report produced by the idle-only objective verification
/// stage. The verdict store persists a bounded review projection, while the
/// complete report and its full candidate evidence remain inside this run.
const maintenanceLl37ObjectiveVerificationReportKey =
    'maintenance.ll37ObjectiveVerificationReport';

/// Run-local aggregate after the latest persisted LL37 vote.
const maintenanceLl37ObjectiveVoteAggregateKey =
    'maintenance.ll37ObjectiveVoteAggregate';

final maintenanceLl37VerifierFidelityRegistryProvider =
    Provider<Ll37VerifierFidelityRegistry>((ref) {
      return const Ll37VerifierFidelityRegistry();
    });

final maintenanceLl37EligibleVerifierProfilesProvider =
    Provider<List<Ll37VerifierFidelityProfile>>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      return ref
          .watch(maintenanceLl37VerifierFidelityRegistryProvider)
          .eligibleProfiles(
            provider: settings.llmProvider,
            baseUrl: settings.baseUrl,
          );
    });

final maintenanceLl37WorktreeAgentCandidateAdapterProvider =
    Provider<Ll37WorktreeAgentCandidateAdapter>((ref) {
      return const Ll37WorktreeAgentCandidateAdapter();
    });

final maintenanceLl37RoutineCandidateAdapterProvider =
    Provider<Ll37RoutineCandidateAdapter>((ref) {
      return const Ll37RoutineCandidateAdapter();
    });

final maintenanceLl37RetryUntilGreenCandidateAdapterProvider =
    Provider<Ll37RetryUntilGreenCandidateAdapter>((ref) {
      return const Ll37RetryUntilGreenCandidateAdapter();
    });

final maintenanceLl37ObjectiveAttemptLedgerProvider =
    Provider<Ll37ObjectiveAttemptLedger>((ref) {
      return Ll37ObjectiveAttemptLedger();
    });

final maintenanceLl37ObjectiveVerdictProjectionBuilderProvider =
    Provider<Ll37ObjectiveVerdictProjectionBuilder>((ref) {
      return const Ll37ObjectiveVerdictProjectionBuilder();
    });

final maintenanceLl37ObjectiveVotePolicyProvider =
    Provider<Ll37ObjectiveVotePolicy>((ref) {
      return const Ll37ObjectiveVotePolicy();
    });

/// Supplies a read-only projection of all complete unattended source history.
/// Loading repositories does not instantiate execution notifiers, recover or
/// resume work, inspect workspaces, rerun verification, or write persistence.
final maintenanceLl37ObjectiveCandidateSourceProvider =
    Provider<Future<List<Ll37ObjectiveCandidate>> Function()>((ref) {
      return () async {
        final candidates = <Ll37ObjectiveCandidate>[
          ...ref
              .read(maintenanceLl37WorktreeAgentCandidateAdapterProvider)
              .adapt(ref.read(worktreeAgentTaskRepositoryProvider).loadAll()),
          ...ref
              .read(maintenanceLl37RoutineCandidateAdapterProvider)
              .adapt(ref.read(routineRepositoryProvider).loadAll()),
          ...ref
              .read(maintenanceLl37RetryUntilGreenCandidateAdapterProvider)
              .adapt(
                ref.read(retryUntilGreenReportRepositoryProvider).loadAll(),
              ),
        ];
        final seenIds = <String>{};
        return List.unmodifiable(
          candidates.where((candidate) => seenIds.add(candidate.id)),
        );
      };
    });

/// Fail-closed fidelity gate for a provider and endpoint with measured routes.
final maintenanceLl37VerifierFidelityEligibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(maintenanceLl37EligibleVerifierProfilesProvider).isNotEmpty,
);

typedef Ll37ObjectiveVerificationPanelFactory =
    Ll37ObjectiveVerificationPanel Function(
      Ll37VerifierFidelityProfile profile,
    );

/// Builds a tool-free panel for one measured route and rechecks that route
/// against live provider and endpoint settings immediately before the request.
final maintenanceLl37ObjectiveVerificationPanelFactoryProvider =
    Provider<Ll37ObjectiveVerificationPanelFactory>((ref) {
      return (selectedProfile) => Ll37ObjectiveVerificationPanel(
        complete: (prompt, maxOutputTokens) async {
          final settings = ref.read(settingsNotifierProvider);
          final eligibleProfiles = ref
              .read(maintenanceLl37VerifierFidelityRegistryProvider)
              .eligibleProfiles(
                provider: settings.llmProvider,
                baseUrl: settings.baseUrl,
              );
          final routeStillEligible = eligibleProfiles.any(
            (profile) =>
                profile.profileKey == selectedProfile.profileKey &&
                profile.reportSha256.toLowerCase() ==
                    selectedProfile.reportSha256.toLowerCase(),
          );
          if (!routeStillEligible) {
            throw const Ll37ObjectiveVerifierPreconditionException(
              'The selected verifier route is no longer eligible for the '
              'active provider and endpoint.',
            );
          }
          final now = DateTime.now();
          final result = await ModelUsageRole.eval.runWith(
            () => ref
                .read(chatRemoteDataSourceProvider)
                .createChatCompletion(
                  messages: [
                    Message(
                      id: 'll37-idle-verifier-${now.microsecondsSinceEpoch}',
                      content: prompt,
                      role: MessageRole.user,
                      timestamp: now,
                    ),
                  ],
                  tools: const [],
                  model: selectedProfile.model,
                  temperature: 0,
                  maxTokens: maxOutputTokens,
                ),
          );
          return result.content;
        },
      );
    });

/// Extracts the instruction overrides from a [ModelHarnessConfig] as a single
/// suffix suitable for appending to the replay system prompt. Used by the
/// adoption eval runners to inject the candidate's instruction changes without
/// mutating live settings.
String _harnessSystemPromptSuffix(ModelHarnessConfig? config) {
  if (config == null) return '';
  final parts = [
    config.bootstrapInstruction.trim(),
    config.executionInstruction.trim(),
    config.verificationInstruction.trim(),
    config.failureRecoveryInstruction.trim(),
  ].where((p) => p.isNotEmpty).toList();
  return parts.join('\n\n');
}

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

/// Builds a [PersonalEvalCaseRunner] with the instruction overrides of the
/// given [ModelHarnessConfig] injected into the replay system prompt. Used by
/// the LL17 adopt stage to compare incumbent vs candidate harness configs
/// without mutating live settings.
///
/// Override in tests to inject fake runners.
final maintenanceEvalRunnerFactoryProvider =
    Provider<PersonalEvalCaseRunner Function(ModelHarnessConfig? config)>((
      ref,
    ) {
      final runnerWithSuffix = ref.read(
        personalEvalRunnerWithSuffixFactoryProvider,
      );
      return (config) => runnerWithSuffix(_harnessSystemPromptSuffix(config));
    });

/// The ordered maintenance stages run on each idle window:
/// probe -> calibrate -> eval -> mine -> propose -> adopt -> precompute ->
/// warm_cache.
///
/// Wired today: re-probe the active model (LL3/LL21), sampler calibration via
/// the full diagnostic (LL16), a baseline eval over the recorded suite (LL19),
/// LL17 weakness mining that clusters failure traces, and an LL17 propose stage
/// that turns the top cluster into one minimal grounded harness edit. Adopt
/// surfaces that edit as a recommendation; auto-applying it on candidate-applied
/// held-in/held-out validation is the remaining LL17 piece. The trailing LL22
/// stages precompute the repo map and warm the server-side prefix KV cache so
/// the morning's first interactive turn is fast — run last so earlier stages'
/// requests do not evict the warmed prefix from the server slot.
final maintenanceStagesProvider = Provider<List<MaintenanceStage>>((ref) {
  return [
    CallbackMaintenanceStage(
      name: 'probe',
      body: (_) async {
        await ref
            .read(modelCapabilityAutoProbeNotifierProvider.notifier)
            .runForCurrentModel(force: true, source: 'idle_re_probe');
        // LL21: report whether the re-probe detected a capability change vs
        // the previous revision (potential GGUF/model-weight swap).
        final revisions = ref
            .read(settingsNotifierProvider)
            .effectiveModelProfileRevisions;
        final latest = revisions.isNotEmpty ? revisions.first : null;
        if (latest != null && latest.capabilityChangeDetected) {
          return const MaintenanceStageOutcome.completed(
            're-probed active model; capability change detected '
            '(possible model swap)',
          );
        }
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
        // LL39: this is the only place the benchmark runs unattended, so the
        // score has to reach the morning report — otherwise a nightly
        // regression is measured, stored, and never read.
        final settings = ref.read(settingsNotifierProvider);
        final profile = settings.effectiveModelCapabilityProfile;
        final summary = profile == null
            ? null
            : ModelBenchmarkHistory.forProfile(
                revisions: settings.modelCapabilityProfileRevisions,
                profileId: profile.computedId,
                suite: profile.probeMetadata['benchmarkSuite'] ?? '',
              ).summaryLine();
        return MaintenanceStageOutcome.completed(
          summary == null
              ? 'ran diagnostic + sampler calibration'
              : 'ran diagnostic + sampler calibration; $summary',
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
      name: 'objective_verify',
      body: (context) async {
        final profiles = ref.read(
          maintenanceLl37EligibleVerifierProfilesProvider,
        );
        if (profiles.isEmpty) {
          return const MaintenanceStageOutcome.skipped(
            'verifier fidelity profile is not eligible',
          );
        }
        final routes = profiles
            .map(
              (profile) => Ll37ObjectiveVoteRoute(
                verifierProfileKey: profile.profileKey,
                fidelityReportSha256: profile.reportSha256,
              ),
            )
            .toList(growable: false);
        final candidates = await ref.read(
          maintenanceLl37ObjectiveCandidateSourceProvider,
        )();
        if (candidates.isEmpty) {
          return const MaintenanceStageOutcome.skipped(
            'no unattended objective candidates',
          );
        }
        final history = ref.read(ll37ObjectiveVerdictHistoryNotifierProvider);
        final policy = ref.read(maintenanceLl37ObjectiveVotePolicyProvider);
        final attemptLedger = ref.read(
          maintenanceLl37ObjectiveAttemptLedgerProvider,
        );
        Ll37ObjectiveCandidate? candidate;
        Ll37ObjectiveVotePlan? votePlan;
        for (final item in candidates) {
          final candidatePlan = policy.plan(
            candidateId: item.id,
            routes: routes,
            history: history,
          );
          final voteId = candidatePlan.nextVoteId;
          if (candidatePlan.shouldRequest &&
              voteId != null &&
              !attemptLedger.contains(voteId)) {
            candidate = item;
            votePlan = candidatePlan;
            break;
          }
        }
        if (candidate == null || votePlan == null) {
          return const MaintenanceStageOutcome.skipped(
            'no unattended objective candidates require another vote',
          );
        }
        final voteId = votePlan.nextVoteId!;
        final voteIndex = votePlan.nextVoteIndex!;
        final nextRoute = votePlan.nextRoute!;
        final profile = profiles.firstWhere(
          (item) =>
              item.profileKey == nextRoute.normalizedProfileKey &&
              item.reportSha256.toLowerCase() ==
                  nextRoute.normalizedReportSha256,
        );
        final firstAttempt = ref
            .read(maintenanceLl37ObjectiveAttemptLedgerProvider)
            .record(voteId);
        if (!firstAttempt) {
          return const MaintenanceStageOutcome.skipped(
            'objective vote was already attempted this session',
          );
        }
        final report = await ref
            .read(maintenanceLl37ObjectiveVerificationPanelFactoryProvider)(
              profile,
            )
            .evaluate(
              candidate: candidate,
              isCancelled: () => context.isCancelled,
            );
        context.shared[maintenanceLl37ObjectiveVerificationReportKey] = report;
        if (report.status != Ll37ObjectivePanelStatus.evaluated) {
          return MaintenanceStageOutcome.skipped(
            'objective verification ${report.status.name}: ${report.detail}',
          );
        }
        final record = ref
            .read(maintenanceLl37ObjectiveVerdictProjectionBuilderProvider)
            .build(
              voteId: voteId,
              voteIndex: voteIndex,
              candidate: candidate,
              report: report,
              profile: profile,
              recordedAt: context.now(),
            );
        await ref
            .read(ll37ObjectiveVerdictHistoryNotifierProvider.notifier)
            .record(record);
        final aggregate = policy
            .plan(
              candidateId: candidate.id,
              routes: routes,
              history: ref.read(ll37ObjectiveVerdictHistoryNotifierProvider),
            )
            .aggregate;
        context.shared[maintenanceLl37ObjectiveVoteAggregateKey] = aggregate;
        final queued = candidates.length > 1
            ? '; evaluated first of ${candidates.length}'
            : '';
        return MaintenanceStageOutcome.completed(
          'objective vote $voteIndex/'
          '${aggregate.maxVoteCount} ${report.verdict!.verdict.name}; '
          'route ${profile.model}; '
          'aggregate ${aggregate.status.name}/${aggregate.outcome.name}; '
          'estimated tokens ${report.estimatedTotalTokens}; '
          'persisted vote$queued',
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
        // High-risk surfaces are blocked immediately, before touching any live
        // providers, so this check works even in restricted test containers.
        if (CandidateAdoptionService.highRiskSurfaces.contains(
          proposal.surface,
        )) {
          return MaintenanceStageOutcome.completed(
            'manual review required: surface ${proposal.surface} '
            'requires manual review before adoption',
          );
        }
        // Check for eval cases before building the runner factory: reading
        // maintenanceEvalRunnerFactoryProvider cascades into settings providers
        // that need SharedPreferences, so we skip early when there's nothing
        // to run against.
        final cases =
            ref.read(personalEvalCasesNotifierProvider).value ?? const [];
        if (cases.isEmpty) {
          return const MaintenanceStageOutcome.skipped(
            'no recorded eval cases to validate against',
          );
        }
        final runnerFactory = ref.read(maintenanceEvalRunnerFactoryProvider);
        final incumbentConfig = ref
            .read(settingsNotifierProvider)
            .effectiveModelHarnessConfig;
        final outcome = await const CandidateAdoptionService().evaluate(
          proposal: proposal,
          cases: cases,
          incumbentRunner: runnerFactory(incumbentConfig),
          candidateRunner: runnerFactory(proposal.proposedConfig),
          persist: ref
              .read(settingsNotifierProvider.notifier)
              .upsertModelHarnessConfig,
        );
        return switch (outcome.status) {
          CandidateAdoptionStatus.adopted => MaintenanceStageOutcome.completed(
            'adopted ${proposal.surface} for ${proposal.mechanism}: '
            '${outcome.reason}',
          ),
          CandidateAdoptionStatus.rejected => MaintenanceStageOutcome.completed(
            'rejected ${proposal.surface} for ${proposal.mechanism}: '
            '${outcome.reason}',
          ),
          CandidateAdoptionStatus.skipped => MaintenanceStageOutcome.skipped(
            outcome.reason,
          ),
          CandidateAdoptionStatus.manualReview =>
            MaintenanceStageOutcome.completed(
              'manual review required: ${outcome.reason}',
            ),
        };
      },
    ),
    // LL22 idle warm-up runs last, after probe/calibrate/eval have sent their
    // own requests, so the prefix this warms is the one left in the server slot
    // for the morning's first interactive turn.
    CallbackMaintenanceStage(
      name: 'precompute',
      body: (_) async {
        // LL22: precompute the LL4 repo map so the first morning prompt build
        // is a cache hit instead of a full symbol-extraction scan.
        final project = ref
            .read(codingProjectsNotifierProvider)
            .selectedProject;
        if (project == null) {
          return const MaintenanceStageOutcome.skipped(
            'no active coding project',
          );
        }
        final settings = ref.read(settingsNotifierProvider);
        final result = ref
            .read(repoMapPrecomputeCacheProvider)
            .precompute(
              rootPath: project.rootPath,
              usableContextTokens:
                  settings.effectiveModelCapabilityProfile?.usableContextTokens,
            );
        return switch (result) {
          RepoMapPrecomputeResult.computed =>
            const MaintenanceStageOutcome.completed('precomputed repo map'),
          RepoMapPrecomputeResult.alreadyWarm =>
            const MaintenanceStageOutcome.completed('repo map already warm'),
          RepoMapPrecomputeResult.noProject =>
            const MaintenanceStageOutcome.skipped('no buildable repo map'),
        };
      },
    ),
    CallbackMaintenanceStage(
      name: 'warm_cache',
      body: (_) async {
        // LL22 KV warm-up: prime the server-side prefix cache so the morning's
        // first turn reuses it. Only meaningful for an OpenAI-compatible server
        // running the LL6 prefix-stable tool loop.
        final settings = ref.read(settingsNotifierProvider);
        if (settings.llmProvider != LlmProvider.openAiCompatible) {
          return const MaintenanceStageOutcome.skipped(
            'on-device provider has no server cache to warm',
          );
        }
        if (!settings.enablePrefixStableToolLoop) {
          return const MaintenanceStageOutcome.skipped(
            'prefix-stable tool loop disabled',
          );
        }
        final mcpToolService = ref.read(mcpToolServiceProvider);
        if (mcpToolService == null) {
          return const MaintenanceStageOutcome.skipped(
            'tool service unavailable',
          );
        }

        final tools = mcpToolService.getOpenAiToolDefinitions();
        final toolNames = <String>[];
        for (final tool in tools) {
          final function = tool['function'];
          if (function is Map) {
            final name = function['name'];
            if (name is String && name.isNotEmpty) toolNames.add(name);
          }
        }

        final project = ref
            .read(codingProjectsNotifierProvider)
            .selectedProject;
        final repoMap = project == null
            ? null
            : ref
                  .read(repoMapPrecomputeCacheProvider)
                  .getOrBuild(
                    rootPath: project.rootPath,
                    usableContextTokens: settings
                        .effectiveModelCapabilityProfile
                        ?.usableContextTokens,
                  );

        final systemPrompt = SystemPromptBuilder.build(
          now: DateTime.now(),
          // Coding mode is the warm-up target: it carries the repo map and the
          // full agentic tool guidance the first morning turn will send.
          assistantMode: AssistantMode.coding,
          languageCode: settings.language == 'system'
              ? 'en'
              : settings.language,
          toolNames: toolNames,
          projectName: project?.name,
          projectRootPath: project?.rootPath,
          repoMapContext: repoMap,
          modelCapabilityProfile: settings.effectiveModelCapabilityProfile,
          modelHarnessConfig: settings.effectiveModelHarnessConfig,
        );

        final dataSource = ref.read(chatRemoteDataSourceProvider);
        final outcome = await const KvCacheWarmupService().warm(
          systemPrompt: systemPrompt,
          tools: tools,
          send:
              ({
                required messages,
                required tools,
                required maxTokens,
                required temperature,
              }) async {
                await dataSource.createChatCompletion(
                  messages: messages,
                  tools: tools,
                  model: settings.effectiveModel,
                  maxTokens: maxTokens,
                  temperature: temperature,
                );
              },
        );

        return switch (outcome.status) {
          KvCacheWarmupStatus.warmed => MaintenanceStageOutcome.completed(
            outcome.detail,
          ),
          KvCacheWarmupStatus.skipped => MaintenanceStageOutcome.skipped(
            outcome.detail,
          ),
          // Best-effort: an unreachable overnight endpoint is a soft skip, not a
          // run failure that flags the morning report red.
          KvCacheWarmupStatus.failed => MaintenanceStageOutcome.skipped(
            'warm-up could not reach endpoint: ${outcome.detail}',
          ),
        };
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
