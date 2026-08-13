import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_vote_identity.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_approved_repair_task_adapter.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:caverno/features/maintenance/presentation/pages/idle_maintenance_debug_page.dart';
import 'package:caverno/features/maintenance/presentation/providers/ll37_approved_repair_task_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/ll37_objective_verdict_history_notifier.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _Stage implements MaintenanceStage {
  _Stage(this.name, this.outcome);

  @override
  final String name;
  final MaintenanceStageOutcome outcome;

  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) async =>
      outcome;
}

class _FixedVerdictHistoryNotifier extends Ll37ObjectiveVerdictHistoryNotifier {
  _FixedVerdictHistoryNotifier(this.records);

  final List<Ll37ObjectiveVerdictRecord> records;

  @override
  List<Ll37ObjectiveVerdictRecord> build() => records;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  Future<void> pumpPage(
    WidgetTester tester,
    List<MaintenanceStage> stages, {
    List<Ll37ObjectiveVerdictRecord> verdicts = const [],
    List<WorktreeAgentTask> worktreeAgentTasks = const [],
    Ll37ApprovedRepairTaskEnqueue? enqueueRepairTask,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                maintenanceStagesProvider.overrideWithValue(stages),
                ll37ObjectiveVerdictHistoryNotifierProvider.overrideWith(
                  () => _FixedVerdictHistoryNotifier(verdicts),
                ),
                ll37ApprovedRepairTaskSourceProvider.overrideWithValue(
                  () => worktreeAgentTasks,
                ),
                if (enqueueRepairTask != null)
                  ll37ApprovedRepairTaskEnqueueProvider.overrideWithValue(
                    enqueueRepairTask,
                  ),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const IdleMaintenanceDebugPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('run now executes the pipeline and renders the report', (
    tester,
  ) async {
    await pumpPage(tester, [
      _Stage('probe', const MaintenanceStageOutcome.completed('profiled')),
      _Stage('eval', const MaintenanceStageOutcome.skipped('no cases')),
    ]);

    expect(find.byKey(const ValueKey('idle-maintenance-debug-run')), findsOne);

    await tester.tap(find.byKey(const ValueKey('idle-maintenance-debug-run')));
    await tester.pumpAndSettle();

    // Per-stage results render with their detail.
    expect(find.text('probe'), findsOneWidget);
    expect(find.text('profiled'), findsOneWidget);
    expect(find.text('eval'), findsOneWidget);
    expect(find.text('no cases'), findsOneWidget);

    // The formatted markdown report renders.
    expect(find.textContaining('# Idle maintenance report'), findsOneWidget);
    expect(find.textContaining('Idle maintenance: 1 done'), findsOneWidget);
    expect(find.text('No persisted objective verdicts yet.'), findsOneWidget);
  });

  testWidgets('renders an expandable persisted LL37 verdict projection', (
    tester,
  ) async {
    await pumpPage(tester, const [], verdicts: [_verdictRecord()]);

    expect(find.text('Objective verifier history'), findsOneWidget);
    expect(find.text('Refuted'), findsOneWidget);

    await tester.tap(find.text('Refuted'));
    await tester.pumpAndSettle();

    expect(find.text('Set the feature flag.'), findsOneWidget);
    expect(find.text('• The flag is true.'), findsOneWidget);
    expect(find.text('• config.json'), findsOneWidget);
    expect(find.textContaining('1/2 • pending/pending'), findsOneWidget);
    expect(
      find.textContaining('#1 qwen3.6-35b-a3b-vision ll37-v1-'),
      findsOneWidget,
    );
    expect(find.textContaining('The flag remains false.'), findsOneWidget);
    expect(
      find.text(
        'openAiCompatible\n'
        'qwen3.6-35b-a3b-vision\n'
        'http://192.168.100.241:1234/v1',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'c07819b6698dacc2f916f96eab2fdaa29230a63713cb7d7d80a5e12eefb86d3e',
      ),
      findsOneWidget,
    );
    expect(find.text('objective verification completed'), findsOneWidget);
    expect(find.textContaining('changed file contents'), findsNothing);
  });

  testWidgets('groups votes and renders their aggregate verdict', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardText = arguments['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(
      tester,
      const [],
      verdicts: [_verdictRecord(voteIndex: 2), _verdictRecord()],
    );

    expect(find.text('Refuted'), findsOneWidget);
    await tester.tap(find.text('Refuted'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('2/2 • converged/refuted • contradiction'),
      findsOneWidget,
    );
    expect(find.textContaining('#1 qwen3.6-35b-a3b-vision'), findsOneWidget);
    expect(find.textContaining('#2 qwen3.6-27b-vision'), findsOneWidget);
    expect(find.textContaining('repairReview'), findsOneWidget);
    final previewFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data?.contains('Repair the reviewed LL37 objective gaps.') ??
              false),
    );
    expect(previewFinder, findsOneWidget);
    final preview = tester.widget<SelectableText>(previewFinder).data;
    expect(preview, contains('Do not change the objective'));
    expect(preview, isNot(contains('Verification result: passed')));
    expect(clipboardText, isNull);

    final copyButton = find.byKey(
      const ValueKey('ll37-copy-repair-nudge-worktree-agent:task-1'),
    );
    await tester.scrollUntilVisible(
      copyButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(clipboardText, preview);
    expect(find.text('Repair nudge copied.'), findsOneWidget);
  });

  testWidgets('requires a user decision without exposing a repair action', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const [],
      verdicts: [
        _verdictRecord(voteIndex: 2),
        _verdictRecord(voteIndex: 1, blocking: 'none'),
      ],
    );

    expect(find.text('Refuted'), findsOneWidget);
    await tester.tap(find.text('Refuted'));
    await tester.pumpAndSettle();

    expect(find.textContaining('userDecisionRequired'), findsOneWidget);
    expect(find.textContaining('requires a user decision'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('ll37-copy-repair-nudge-worktree-agent:task-1'),
      ),
      findsNothing,
    );
  });

  testWidgets('queues one new LL13 repair task only after confirmation', (
    tester,
  ) async {
    final source = _sourceTask();
    final sourceBefore = source.toJson();
    final queuedSpecs = <Ll37ApprovedRepairTaskSpec>[];
    await pumpPage(
      tester,
      const [],
      verdicts: [_verdictRecord(voteIndex: 2), _verdictRecord()],
      worktreeAgentTasks: [source],
      enqueueRepairTask: (spec) async {
        queuedSpecs.add(spec);
        return _queuedTask(spec);
      },
    );

    await tester.tap(find.text('Refuted'));
    await tester.pumpAndSettle();
    final createButton = find.byKey(
      const ValueKey('ll37-create-repair-task-worktree-agent:task-1'),
    );
    await tester.scrollUntilVisible(
      createButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(queuedSpecs, isEmpty);

    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('Create a new LL13 repair task?'), findsOneWidget);
    expect(find.textContaining('Objective: Set the feature flag.'), findsOne);
    expect(find.textContaining('Verification: dart test'), findsOne);
    expect(queuedSpecs, isEmpty);

    await tester.tap(find.byKey(const ValueKey('ll37-repair-task-cancel')));
    await tester.pumpAndSettle();
    expect(queuedSpecs, isEmpty);
    expect(source.toJson(), sourceBefore);

    await tester.tap(createButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ll37-repair-task-confirm')));
    await tester.pumpAndSettle();

    expect(queuedSpecs, hasLength(1));
    final spec = queuedSpecs.single;
    expect(spec.assignmentId, startsWith('ll37-repair-'));
    expect(spec.sourceTaskId, source.id);
    expect(spec.baseBranch, source.branchName);
    expect(spec.prompt, contains('Repair the reviewed LL37 objective gaps.'));
    expect(
      spec.objectiveAcceptanceCriteria,
      source.objectiveAcceptanceCriteria,
    );
    expect(spec.verificationCommand, source.verificationCommand);
    expect(source.toJson(), sourceBefore);
    expect(
      find.text('Repair task queued on branch feature/repair-task.'),
      findsOneWidget,
    );
    expect(
      find.text('This reviewed repair task is already queued.'),
      findsOneWidget,
    );
    expect(createButton, findsNothing);
  });
}

Ll37ObjectiveVerdictRecord _verdictRecord({
  int voteIndex = 1,
  String blocking = 'contradiction',
}) {
  final profile = Ll37VerifierFidelityRegistry.acceptedProfiles[voteIndex - 1];
  return Ll37ObjectiveVerdictRecord(
    voteId: Ll37ObjectiveVoteIdentity.build(
      candidateId: 'worktree-agent:task-1',
      verifierProfileKey: profile.profileKey,
      fidelityReportSha256: profile.reportSha256,
      voteIndex: voteIndex,
    ),
    voteIndex: voteIndex,
    candidateId: 'worktree-agent:task-1',
    sourceSurface: 'worktreeAgent',
    objective: 'Set the feature flag.',
    acceptanceCriteria: const ['The flag is true.'],
    changedFilePaths: const ['config.json'],
    implementationEvidence: const ['Verification result: passed'],
    verdict: blocking == 'none' ? 'notRefuted' : 'refuted',
    confidence: 0.9,
    blocking: blocking,
    findings: blocking == 'none'
        ? const []
        : const [
            Ll37ObjectiveVerdictFindingRecord(
              kind: 'unmet_criterion',
              location: 'config.json',
              detail: 'The flag remains false.',
            ),
          ],
    detail: 'objective verification completed',
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verifierProvider: 'openAiCompatible',
    verifierBaseUrl: profile.baseUrl,
    verifierModel: profile.model,
    verifierProfileKey: profile.profileKey,
    fidelityReportSchemaVersion: 3,
    fidelityReportSha256: profile.reportSha256,
    recordedAt: DateTime.utc(2026, 8, 13, 0, voteIndex),
  );
}

WorktreeAgentTask _sourceTask() => WorktreeAgentTask(
  id: 'task-1',
  status: WorktreeAgentTaskStatus.completed,
  title: 'Enable the feature flag',
  prompt: 'Set the feature flag.',
  codingProjectId: 'project-1',
  baseBranch: 'main',
  branchName: 'feature/source-task',
  worktreePath: '/tmp/source-task',
  verificationCommand: 'dart test',
  objectiveAcceptanceCriteria: const ['The flag is true.'],
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13, 1),
  finishedAt: DateTime.utc(2026, 8, 13, 1),
  verifiedGreen: true,
);

WorktreeAgentTask _queuedTask(Ll37ApprovedRepairTaskSpec spec) =>
    WorktreeAgentTask(
      id: spec.assignmentId,
      title: spec.title,
      prompt: spec.prompt,
      codingProjectId: spec.codingProjectId,
      baseBranch: spec.baseBranch,
      branchName: 'feature/repair-task',
      worktreePath: '/tmp/repair-task',
      verificationCommand: spec.verificationCommand,
      objectiveAcceptanceCriteria: spec.objectiveAcceptanceCriteria,
      createdAt: DateTime.utc(2026, 8, 13, 2),
      updatedAt: DateTime.utc(2026, 8, 13, 2),
    );
