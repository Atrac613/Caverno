import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

class _MockConversationBox extends Mock implements Box<String> {}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

void main() {
  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
      ],
    );
  }

  test(
    'recordCurrentGoalTurn completes active goals from final evidence',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Fix the login crash',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Goal complete. Tests passed.',
        tokenUsageDelta: 120,
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.completed);
      expect(goal.tokenUsage, 120);
      expect(goal.turnsUsed, 1);
      expect(goal.completedAt, isNotNull);
    },
  );

  test(
    'recordCurrentGoalTurn completes active goals from Japanese final evidence',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Save a Tokyo weather report as Markdown',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse:
            '\u6771\u4eac\u306e\u660e\u65e5\uff082026\u5e746\u67083\u65e5\uff09\u306e\u5929\u6c17\u3092\u8abf\u3079\u3001'
            '\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u65e2\u5b58\u30d5\u30a1\u30a4\u30eb\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002',
        tokenUsageDelta: 150,
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.completed);
      expect(goal.tokenUsage, 150);
      expect(goal.turnsUsed, 1);
      expect(goal.completedAt, isNotNull);
    },
  );

  test(
    'recordCurrentGoalTurn completes when only unverified evidence remains',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Build the TODO CLI and verify it',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Goal complete. Tests passed.',
        tokenUsageDelta: 90,
        completionEvidence: const ToolResultCompletionEvidence(
          unverifiedChangePaths: ['bin/todo_cli.dart'],
        ),
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.completed);
      expect(goal.tokenUsage, 90);
      expect(goal.turnsUsed, 1);
      expect(goal.completedAt, isNotNull);
    },
  );

  test(
    'recordCurrentGoalTurn does not complete when unresolved errors remain',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Build the TODO CLI and verify it',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Goal complete. Tests passed.',
        tokenUsageDelta: 90,
        completionEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: ['bin/todo_cli.dart'],
        ),
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.active);
      expect(goal.tokenUsage, 90);
      expect(goal.turnsUsed, 1);
      expect(goal.completedAt, isNull);
    },
  );

  test(
    'recordCurrentGoalTurn keeps the goal active while saved tasks remain',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Build the TODO CLI',
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Initialize the project',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
            ConversationWorkflowTask(id: 'task-2', title: 'Implement the CLI'),
          ],
        ),
      );
      await notifier.saveCurrentGoal(
        objective: 'Build the TODO CLI',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse:
            'Task 1 is complete. The saved validation exited with code 0.',
        tokenUsageDelta: 80,
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.active);
      expect(goal.turnsUsed, 1);
      expect(goal.completedAt, isNull);
    },
  );

  test('recordCurrentGoalTurn blocks after repeated same blocker', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(conversationsNotifierProvider.notifier);

    notifier.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
    );
    await notifier.saveCurrentGoal(
      objective: 'Update the project settings',
      enabled: true,
      status: ConversationGoalStatus.active,
    );

    for (var index = 0; index < 3; index++) {
      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Blocked: permission denied while reading settings.',
        tokenUsageDelta: 10,
      );
    }

    final goal = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .goal!;
    expect(goal.status, ConversationGoalStatus.blocked);
    expect(goal.blockerRepeatCount, 3);
    expect(goal.blockedAt, isNotNull);
  });

  test('saveCurrentGoal stores and preserves the auto-continue flag', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(conversationsNotifierProvider.notifier);

    notifier.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
    );
    await notifier.saveCurrentGoal(
      objective: 'Fix the parser',
      enabled: true,
      status: ConversationGoalStatus.active,
      autoContinue: true,
      tokenBudget: 1000,
      turnBudget: 5,
    );

    var goal = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .goal!;
    expect(goal.autoContinue, isTrue);

    await notifier.saveCurrentGoal(
      objective: 'Fix the parser',
      enabled: false,
      status: ConversationGoalStatus.active,
      tokenBudget: 2000,
      turnBudget: 6,
    );

    goal = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .goal!;
    expect(goal.autoContinue, isTrue);

    await notifier.saveCurrentGoal(
      objective: 'Fix the parser',
      enabled: true,
      status: ConversationGoalStatus.active,
      autoContinue: false,
    );

    goal = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .goal!;
    expect(goal.autoContinue, isFalse);
  });

  test('recordCurrentGoalTurn blocks after equivalent blocker wording', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(conversationsNotifierProvider.notifier);

    notifier.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
    );
    await notifier.saveCurrentGoal(
      objective: 'Update the project settings',
      enabled: true,
      status: ConversationGoalStatus.active,
    );

    for (final response in const [
      'Blocked: permission denied while reading `/tmp/project/settings.json`.',
      'Cannot proceed because permission was denied when reading /var/settings.json.',
      'I am blocked: access denied while reading the settings file.',
    ]) {
      await notifier.recordCurrentGoalTurn(
        assistantResponse: response,
        tokenUsageDelta: 10,
      );
    }

    final goal = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .goal!;
    expect(goal.status, ConversationGoalStatus.blocked);
    expect(goal.blockerSignature, 'permission denied reading');
    expect(goal.blockerRepeatCount, 3);
    expect(goal.blockedAt, isNotNull);
  });

  test(
    'recordCurrentGoalTurn completes the goal from an update_goal claim '
    'when the response carries no completion prose',
    () async {
      // The regression from session f2a25c20: the tool tells the model that
      // prose is not how a goal is finished, so a model that obeys leaves no
      // completion prose — and the goal ran forever because only the lexical
      // path could complete it. Verified against a negative control: with
      // toolCompletionClaimed false this response does not complete the goal.
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Fix the login crash',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Ran the acceptance checks.',
        tokenUsageDelta: 10,
        toolCompletionClaimed: true,
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.completed);
      expect(goal.completedAt, isNotNull);
    },
  );

  test(
    'recordCurrentGoalTurn keeps the goal active when a tool completion '
    'claim is contradicted by blocking evidence',
    () async {
      // The claim is judged against the finalization evidence, not against the
      // partial evidence the ack saw mid-turn. In f2a25c20 the claim arrived
      // with five unresolved errors still outstanding.
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Fix the login crash',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Ran the acceptance checks.',
        tokenUsageDelta: 10,
        toolCompletionClaimed: true,
        completionEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 5,
          unresolvedErrorPaths: ['lib/todo.dart'],
        ),
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.active);
      expect(goal.completedAt, isNull);
    },
  );

  test(
    'recordCurrentGoalTurn keeps the goal active when a tool completion '
    'claim follows a mutation with no execution verification',
    () async {
      // Completing the goal ends the run, because auto-continue only fires
      // while the goal is active. A mutation with no verification carries no
      // *blocking* evidence but is exactly the state the grounded-verification
      // track exists to keep working on, so it must not end the run.
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Fix the login crash',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Edited the handler.',
        tokenUsageDelta: 10,
        toolCompletionClaimed: true,
        completionEvidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          unverifiedChangePaths: ['lib/login.dart'],
        ),
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.active);
      expect(goal.completedAt, isNull);
    },
  );

  test(
    'recordCurrentGoalTurn reactivates a goal that was awaiting confirmation',
    () async {
      // The waiting label means "nothing is scheduled". A turn just ran, so
      // the goal is working again and must not keep a stale badge.
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      await notifier.saveCurrentGoal(
        objective: 'Fix the login crash',
        enabled: true,
        status: ConversationGoalStatus.awaitingConfirmation,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      await notifier.recordCurrentGoalTurn(
        assistantResponse: 'Still working on the handler.',
        tokenUsageDelta: 10,
      );

      final goal = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .goal!;
      expect(goal.status, ConversationGoalStatus.active);
    },
  );

  test('a goal awaiting confirmation still counts as active', () {
    // Auto-continue and the turn recorder both gate on isActive; excluding
    // this status would strand the goal permanently, since the reset that
    // clears the label lives behind that same gate.
    final goal = ConversationGoal(
      id: 'g',
      objective: 'Fix the login crash',
      status: ConversationGoalStatus.awaitingConfirmation,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
    );
    expect(goal.isActive, isTrue);
    expect(goal.isAwaitingConfirmation, isTrue);
  });
}
