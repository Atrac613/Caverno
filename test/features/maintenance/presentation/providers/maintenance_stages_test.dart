import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PassingRunner implements PersonalEvalCaseRunner {
  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    return const PersonalEvalCaseRunOutcome(
      verificationResult: PersonalEvalVerificationResult.passed,
    );
  }
}

class _FakeCasesNotifier extends PersonalEvalCasesNotifier {
  _FakeCasesNotifier(this._cases);
  final List<PersonalEvalCase> _cases;

  @override
  Future<List<PersonalEvalCase>> build() async => _cases;
}

class _FakeCodingProjectsNotifier extends CodingProjectsNotifier {
  _FakeCodingProjectsNotifier(this._state);
  final CodingProjectsState _state;

  @override
  CodingProjectsState build() => _state;
}

void main() {
  // Building the provider only constructs the stage objects; the probe /
  // calibrate / eval bodies are lazy (they hit notifiers only when run), so the
  // structure and the adopt gating can be tested without LLM overrides.
  List<MaintenanceStage> stages() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(maintenanceStagesProvider);
  }

  MaintenanceStageContext context([Map<String, Object?>? shared]) =>
      MaintenanceStageContext(
        handle: IdleMaintenanceRunHandle(),
        shared: shared ?? <String, Object?>{},
      );

  test('wires probe -> calibrate -> eval -> mine -> propose -> adopt -> '
      'precompute -> warm_cache, warm-up last', () {
    expect(stages().map((s) => s.name), [
      'probe',
      'calibrate',
      'eval',
      'mine',
      'propose',
      'adopt',
      'precompute',
      'warm_cache',
    ]);
  });

  test('precompute skips when there is no active coding project', () async {
    final container = ProviderContainer(
      overrides: [
        codingProjectsNotifierProvider.overrideWith(
          () => _FakeCodingProjectsNotifier(
            const CodingProjectsState(projects: [], selectedProjectId: null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final precompute = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'precompute');
    final outcome = await precompute.run(context());

    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no active coding project'));
  });

  test(
    'warm_cache skips when the prefix-stable tool loop is disabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final warm = container
          .read(maintenanceStagesProvider)
          .firstWhere((s) => s.name == 'warm_cache');
      final outcome = await warm.run(context());

      expect(outcome.status, MaintenanceStageStatus.skipped);
      expect(outcome.detail, contains('prefix-stable tool loop disabled'));
    },
  );

  test('mine skips when there are no failure traces', () async {
    final container = ProviderContainer(
      overrides: [
        maintenanceFailureTraceSourceProvider.overrideWithValue(
          () async => const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final mine = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'mine');
    final outcome = await mine.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no failure traces'));
  });

  test('propose skips when no weakness was mined', () async {
    final propose = stages().firstWhere((s) => s.name == 'propose');
    final outcome = await propose.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no mined weakness'));
  });

  test('mine reports the clustered weaknesses when traces exist', () async {
    const signature = FailureSignature(
      terminalCause: 'edit_apply_failed',
      causalStatus: 'tests_failed',
      mechanism: 'stale_old_text',
    );
    final container = ProviderContainer(
      overrides: [
        maintenanceFailureTraceSourceProvider.overrideWithValue(
          () async => const [
            FailureTrace(caseId: 'a', signature: signature),
            FailureTrace(caseId: 'b', signature: signature),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    final mine = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'mine');
    final outcome = await mine.run(context());

    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, contains('mined 1 cluster(s)'));
    expect(outcome.detail, contains('x2'));
  });

  test('adopt skips when no candidate has been proposed', () async {
    final adopt = stages().firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no candidate proposed'));
  });

  test('adopt skips when eval cases are not available', () async {
    // The bare container has no eval cases loaded, so adopt falls through to
    // the eval-gated path and skips because there is nothing to validate against.
    final adopt = stages().firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(
      context({
        maintenanceProposedCandidateKey: const HarnessConfigProposal(
          mechanism: 'stale_old_text',
          surface: 'failureRecoveryInstruction',
          rationale: 'r',
          proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
        ),
      }),
    );
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no recorded eval cases'));
  });

  test(
    'adopt surfaces manual-review when proposal touches a high-risk surface',
    () async {
      // A high-risk surface is blocked even when eval cases would be available.
      final adopt = stages().firstWhere((s) => s.name == 'adopt');
      final outcome = await adopt.run(
        context({
          maintenanceProposedCandidateKey: const HarnessConfigProposal(
            mechanism: 'some_mechanism',
            surface: 'approvalMode',
            rationale: 'r',
            proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
          ),
        }),
      );
      expect(outcome.status, MaintenanceStageStatus.completed);
      expect(outcome.detail, contains('manual review required'));
      expect(outcome.detail, contains('approvalMode'));
    },
  );

  test('adopt auto-adopts when eval passes on both splits', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const proposal = HarnessConfigProposal(
      mechanism: 'stale_old_text',
      surface: 'failureRecoveryInstruction',
      rationale: 'r',
      proposedConfig: ModelHarnessConfig(
        id: 'p',
        model: 'm',
        failureRecoveryInstruction: 're-read before retry',
      ),
    );
    final evalCase = PersonalEvalCase(
      caseId: 'c1',
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Inject a runner factory that always passes so no live providers needed.
        maintenanceEvalRunnerFactoryProvider.overrideWithValue(
          (_) => _PassingRunner(),
        ),
        personalEvalCasesNotifierProvider.overrideWith(
          () => _FakeCasesNotifier([evalCase]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Wait for the cases notifier to finish loading.
    await container.read(personalEvalCasesNotifierProvider.future);

    final adopt = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(
      context({maintenanceProposedCandidateKey: proposal}),
    );
    // Eval passes → adopted, not just recommended.
    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, contains('adopted'));
    expect(outcome.detail, contains('failureRecoveryInstruction'));
  });
}
