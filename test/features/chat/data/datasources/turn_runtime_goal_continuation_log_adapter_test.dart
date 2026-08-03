import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/turn_runtime_goal_continuation_log_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_continuation_log_record_builder.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late LlmSessionLogStore store;
  const context = LlmSessionLogContext(
    workspaceMode: WorkspaceMode.coding,
    sessionId: 'conversation-a',
    conversationId: 'conversation-a',
  );
  final recordedAt = DateTime.utc(2026, 8, 3, 12, 30);

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'turn_runtime_goal_continuation_log_',
    );
    store = LlmSessionLogStore(rootDirectoryProvider: () async => root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('persists the typed record through the existing schema', () async {
    final adapter = TurnRuntimeGoalContinuationLogAdapter(
      logStore: store,
      context: context,
      settingsEnabled: true,
      environment: const {},
      clock: () => recordedAt,
    );

    await adapter.record(_record());

    final file = await store.fileForContext(context, create: false);
    final entry = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(entry['operation'], 'goal_auto_continue');
    expect(entry['timestamp'], recordedAt.toIso8601String());
    expect(entry['context']['conversationId'], 'conversation-a');
    expect(entry['goalAutoContinue'], {
      'decision': 'continue',
      'reason': 'incomplete evidence remains',
      'nextTurnNumber': 2,
      'effectiveTurnBudget': 5,
      'evidence': isA<Map<String, dynamic>>(),
    });
  });

  test('writes nothing when the setting disables logging', () async {
    final adapter = TurnRuntimeGoalContinuationLogAdapter(
      logStore: store,
      context: context,
      settingsEnabled: false,
      environment: const {},
    );

    await adapter.record(_record());

    final file = await store.fileForContext(context, create: false);
    expect(file.existsSync(), isFalse);
  });

  test('writes nothing when the environment disables logging', () async {
    final adapter = TurnRuntimeGoalContinuationLogAdapter(
      logStore: store,
      context: context,
      settingsEnabled: true,
      environment: const {LlmSessionLogStore.enabledEnvironmentKey: '0'},
    );

    await adapter.record(_record());

    final file = await store.fileForContext(context, create: false);
    expect(file.existsSync(), isFalse);
  });

  test('environment enablement overrides the disabled setting', () async {
    final adapter = TurnRuntimeGoalContinuationLogAdapter(
      logStore: store,
      context: context,
      settingsEnabled: false,
      environment: const {LlmSessionLogStore.enabledEnvironmentKey: '1'},
      clock: () => recordedAt,
    );

    await adapter.record(_record());

    final file = await store.fileForContext(context, create: false);
    expect(file.existsSync(), isTrue);
  });

  test('enabled owner scope requires explicit configuration', () async {
    final adapter = TurnRuntimeGoalContinuationLogAdapter(
      settingsEnabled: true,
      environment: const {},
    );

    await expectLater(adapter.record(_record()), throwsStateError);
  });

  test('adapter has no notifier, Riverpod, or provider dependency', () {
    final source = File(
      'lib/features/chat/data/datasources/'
      'turn_runtime_goal_continuation_log_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(contains('Provider')));
    expect(source, isNot(contains('dynamic Function')));
  });

  test('production continuation logging uses the runtime adapter', () {
    final continuationSource = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_goal_auto_continue.dart',
    ).readAsStringSync();
    final compositionSource = File(
      'lib/features/chat/presentation/providers/'
      'turn_runtime_production_composition.dart',
    ).readAsStringSync();

    expect(
      compositionSource,
      contains('TurnRuntimeGoalContinuationLogAdapter('),
    );
    expect(continuationSource, contains('.configureLogging('));
    expect(continuationSource, contains('.log.record(record);'));
    expect(continuationSource, isNot(contains('.recordGoalAutoContinue(')));
    final enablementCheck = continuationSource.indexOf(
      'if (!runtimeScope.loggingEnabled) return;',
    );
    final conversationRead = continuationSource.indexOf(
      'final conversation = runtime.goalContinuation.conversationGoal',
      enablementCheck,
    );
    expect(enablementCheck, greaterThanOrEqualTo(0));
    expect(conversationRead, greaterThan(enablementCheck));
  });
}

GoalAutoContinueLogRecord _record() {
  return const GoalContinuationLogRecordBuilder().buildAutoContinue(
    owner: ChatTurnOwner(
      conversationId: 'conversation-a',
      interactionGeneration: 3,
    ),
    decision: 'continue',
    reason: 'incomplete evidence remains',
    goal: null,
    nextTurnNumber: 2,
    effectiveTurnBudget: 5,
    tracker: null,
    evidence: const ToolResultCompletionEvidence(),
    verificationCadence: VerificationCadence.notDue,
    mutationGeneration: null,
    verificationGeneration: null,
    safeBoundary: _safeBoundary(),
  );
}

GoalAutoContinueSafeBoundary _safeBoundary() =>
    const GoalAutoContinueSafeBoundary(
      isLoading: false,
      hasQueuedUserInput: false,
      hasPendingSshConnect: false,
      hasPendingSshCommand: false,
      hasPendingGitCommand: false,
      hasPendingLocalCommand: false,
      hasPendingComputerUseAction: false,
      hasPendingBrowserAction: false,
      hasPendingFileOperation: false,
      hasPendingBleConnect: false,
      hasPendingSerialOpen: false,
      hasPendingParticipantToolApproval: false,
      hasPendingAskUserQuestion: false,
      hasPendingWorkflowDecision: false,
      hasParticipantTurnRuntime: false,
      hasError: false,
    );
