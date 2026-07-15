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
}
