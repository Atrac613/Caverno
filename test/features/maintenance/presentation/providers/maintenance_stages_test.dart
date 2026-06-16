import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('wires the probe -> calibrate -> eval -> mine -> propose -> adopt '
      'stages', () {
    expect(stages().map((s) => s.name), [
      'probe',
      'calibrate',
      'eval',
      'mine',
      'propose',
      'adopt',
    ]);
  });

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

  test('adopt recommends a proposed harness edit (manual review)', () async {
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
    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, contains('recommended harness edit'));
    expect(outcome.detail, contains('stale_old_text'));
  });
}
