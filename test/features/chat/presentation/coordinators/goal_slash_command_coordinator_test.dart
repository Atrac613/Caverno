import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/presentation/coordinators/goal_slash_command_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 7, 17, 14);

class _GoalConversationsNotifier extends ConversationsNotifier {
  _GoalConversationsNotifier(this.conversation);

  final Conversation conversation;
  final operations = <String>[];
  String? savedObjective;
  bool? savedEnabled;
  bool? savedAutoContinue;
  ConversationGoalStatus? savedStatus;
  int? savedTokenBudget;
  int? savedTurnBudget;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> saveCurrentGoal({
    required String objective,
    required bool enabled,
    required ConversationGoalStatus status,
    bool? autoContinue,
    int tokenBudget = 0,
    int turnBudget = 0,
    String? blockedReason,
    String? completionSummary,
  }) async {
    operations.add('save');
    savedObjective = objective;
    savedEnabled = enabled;
    savedAutoContinue = autoContinue;
    savedStatus = status;
    savedTokenBudget = tokenBudget;
    savedTurnBudget = turnBudget;
  }

  @override
  Future<void> setCurrentGoalEnabled(bool enabled) async {
    operations.add('enabled:$enabled');
  }

  @override
  Future<void> markCurrentGoalStatus({
    required ConversationGoalStatus status,
    String? blockedReason,
    String? completionSummary,
  }) async {
    operations.add('status:${status.name}');
  }

  @override
  Future<void> clearCurrentGoal() async {
    operations.add('clear');
  }
}

class _Harness {
  _Harness(this.conversation)
    : notifier = _GoalConversationsNotifier(conversation),
      editorConversations = <Conversation>[],
      sentObjectives = <String>[] {
    container = ProviderContainer(
      overrides: [conversationsNotifierProvider.overrideWith(() => notifier)],
    );
    container.read(conversationsNotifierProvider);
    coordinator = GoalSlashCommandCoordinator(
      conversationsNotifier: notifier,
      showGoalEditor: (conversation) async {
        editorConversations.add(conversation);
      },
      sendInitialPrompt: sentObjectives.add,
      text: _text,
    );
  }

  final Conversation conversation;
  final _GoalConversationsNotifier notifier;
  final List<Conversation> editorConversations;
  final List<String> sentObjectives;
  late final ProviderContainer container;
  late final GoalSlashCommandCoordinator coordinator;

  void dispose() => container.dispose();

  Future<dynamic> handle(
    String args, {
    bool sendObjectiveAsInitialPrompt = false,
  }) {
    return coordinator.handle(
      currentConversation: conversation,
      args: args,
      sendObjectiveAsInitialPrompt: sendObjectiveAsInitialPrompt,
    );
  }
}

void main() {
  test(
    'opens the shared editor when no goal exists and args are empty',
    () async {
      final harness = _Harness(_conversation());
      addTearDown(harness.dispose);

      final result = await harness.handle('');

      expect(result.clearInput, isTrue);
      expect(result.feedbackMessage, isNull);
      expect(harness.editorConversations, [harness.conversation]);
      expect(harness.notifier.operations, isEmpty);
    },
  );

  test(
    'reports truncated status, budgets, paused state, and auto state',
    () async {
      final objective = '${List.filled(130, 'x').join()} trailing';
      final goal = _goal(
        objective: objective,
        enabled: false,
        autoContinue: true,
        status: ConversationGoalStatus.blocked,
        tokenBudget: 2500,
        tokenUsage: 1200,
        turnBudget: 8,
        turnsUsed: 3,
      );
      final harness = _Harness(_conversation(goal: goal));
      addTearDown(harness.dispose);

      final result = await harness.handle('  ');

      expect(result.feedbackMessage, startsWith('chat.slash_goal_status('));
      expect(result.feedbackMessage, contains('objective=${'x' * 117}...'));
      expect(result.feedbackMessage, contains('chat.goal_status_blocked'));
      expect(result.feedbackMessage, contains('chat.slash_goal_status_paused'));
      expect(result.feedbackMessage, contains('used=1.2K'));
      expect(result.feedbackMessage, contains('total=2.5K'));
      expect(result.feedbackMessage, contains('used=3'));
      expect(result.feedbackMessage, contains('total=8'));
      expect(
        result.feedbackMessage,
        contains('chat.goal_auto_continue_running'),
      );
    },
  );

  test('uses unlimited usage labels and default auto turn budget', () async {
    final harness = _Harness(
      _conversation(
        goal: _goal(
          objective: 'Ship safely',
          autoContinue: true,
          tokenUsage: 42,
          turnsUsed: 2,
        ),
      ),
    );
    addTearDown(harness.dispose);

    final result = await harness.handle('');

    expect(result.feedbackMessage, contains('chat.goal_status_active'));
    expect(
      result.feedbackMessage,
      contains('chat.slash_goal_token_usage_unlimited'),
    );
    expect(
      result.feedbackMessage,
      contains('chat.slash_goal_turn_usage_unlimited'),
    );
    expect(result.feedbackMessage, contains('total=10'));
  });

  for (final command in ['pause', 'resume', 'clear', 'auto on', 'auto off']) {
    test('$command requires an existing goal', () async {
      final harness = _Harness(_conversation());
      addTearDown(harness.dispose);

      final result = await harness.handle(command);

      expect(result.clearInput, isFalse);
      expect(result.feedbackMessage, 'chat.slash_goal_none');
      expect(harness.notifier.operations, isEmpty);
    });
  }

  test('pause disables an existing goal', () async {
    final harness = _Harness(_conversation(goal: _goal()));
    addTearDown(harness.dispose);

    final result = await harness.handle(' PAUSE ');

    expect(harness.notifier.operations, ['enabled:false']);
    expect(result.feedbackMessage, 'chat.slash_goal_paused');
  });

  test('resume enables and reactivates a completed goal', () async {
    final harness = _Harness(
      _conversation(goal: _goal(status: ConversationGoalStatus.completed)),
    );
    addTearDown(harness.dispose);

    final result = await harness.handle('resume');

    expect(harness.notifier.operations, ['enabled:true', 'status:active']);
    expect(result.feedbackMessage, 'chat.slash_goal_resumed');
  });

  test('resume does not rewrite an already active status', () async {
    final harness = _Harness(_conversation(goal: _goal()));
    addTearDown(harness.dispose);

    await harness.handle('resume');

    expect(harness.notifier.operations, ['enabled:true']);
  });

  test('clear removes an existing goal', () async {
    final harness = _Harness(_conversation(goal: _goal()));
    addTearDown(harness.dispose);

    final result = await harness.handle('clear');

    expect(harness.notifier.operations, ['clear']);
    expect(result.feedbackMessage, 'chat.goal_cleared');
  });

  for (final enabled in [true, false]) {
    test('auto ${enabled ? 'on' : 'off'} preserves goal fields', () async {
      final goal = _goal(
        objective: 'Keep behavior',
        enabled: false,
        status: ConversationGoalStatus.blocked,
        tokenBudget: 3000,
        turnBudget: 7,
      );
      final harness = _Harness(_conversation(goal: goal));
      addTearDown(harness.dispose);

      final result = await harness.handle('auto ${enabled ? 'on' : 'off'}');

      expect(harness.notifier.savedObjective, 'Keep behavior');
      expect(harness.notifier.savedEnabled, isFalse);
      expect(harness.notifier.savedAutoContinue, enabled);
      expect(harness.notifier.savedStatus, ConversationGoalStatus.blocked);
      expect(harness.notifier.savedTokenBudget, 3000);
      expect(harness.notifier.savedTurnBudget, 7);
      expect(
        result.feedbackMessage,
        enabled
            ? 'chat.goal_auto_continue_enabled'
            : 'chat.goal_auto_continue_disabled',
      );
    });
  }

  for (final args in ['auto', 'auto maybe']) {
    test('$args returns auto usage feedback', () async {
      final harness = _Harness(_conversation(goal: _goal()));
      addTearDown(harness.dispose);

      final result = await harness.handle(args);

      expect(result.clearInput, isFalse);
      expect(result.feedbackMessage, 'chat.slash_goal_auto_usage');
      expect(harness.notifier.operations, isEmpty);
    });
  }

  test(
    'saves a first objective, defaults auto on, and sends initial prompt',
    () async {
      final harness = _Harness(_conversation());
      addTearDown(harness.dispose);

      final result = await harness.handle(
        '  Build the MVP  ',
        sendObjectiveAsInitialPrompt: true,
      );

      expect(harness.notifier.savedObjective, 'Build the MVP');
      expect(harness.notifier.savedEnabled, isTrue);
      expect(harness.notifier.savedAutoContinue, isTrue);
      expect(harness.notifier.savedStatus, ConversationGoalStatus.active);
      expect(harness.notifier.savedTokenBudget, 0);
      expect(harness.notifier.savedTurnBudget, 0);
      expect(harness.sentObjectives, ['Build the MVP']);
      expect(result.feedbackMessage, contains('chat.slash_goal_set'));
    },
  );

  test(
    'preserves budgets and auto state for a replacement objective',
    () async {
      final harness = _Harness(
        _conversation(
          goal: _goal(autoContinue: false, tokenBudget: 5000, turnBudget: 12),
        ),
      );
      addTearDown(harness.dispose);

      await harness.handle('pause the deployment');

      expect(harness.notifier.savedObjective, 'pause the deployment');
      expect(harness.notifier.savedAutoContinue, isNull);
      expect(harness.notifier.savedTokenBudget, 5000);
      expect(harness.notifier.savedTurnBudget, 12);
      expect(harness.sentObjectives, isEmpty);
    },
  );

  test('extracts a trailing auto marker from an objective', () async {
    final harness = _Harness(_conversation(goal: _goal()));
    addTearDown(harness.dispose);

    final result = await harness.handle('Ship release AUTO off');

    expect(harness.notifier.savedObjective, 'Ship release');
    expect(harness.notifier.savedAutoContinue, isFalse);
    expect(result.feedbackMessage, contains('chat.slash_goal_set_auto'));
    expect(result.feedbackMessage, contains('chat.goal_auto_continue_off'));
  });
}

Conversation _conversation({ConversationGoal? goal}) => Conversation(
  id: 'conversation-1',
  title: 'Goal test',
  messages: const [],
  createdAt: _now,
  updatedAt: _now,
  workspaceMode: WorkspaceMode.coding,
  projectId: 'project-1',
  goal: goal,
);

ConversationGoal _goal({
  String objective = 'Complete the task',
  bool enabled = true,
  bool autoContinue = false,
  ConversationGoalStatus status = ConversationGoalStatus.active,
  int tokenBudget = 0,
  int tokenUsage = 0,
  int turnBudget = 0,
  int turnsUsed = 0,
}) => ConversationGoal(
  id: 'goal-1',
  objective: objective,
  enabled: enabled,
  autoContinue: autoContinue,
  status: status,
  tokenBudget: tokenBudget,
  tokenUsage: tokenUsage,
  turnBudget: turnBudget,
  turnsUsed: turnsUsed,
  createdAt: _now,
  updatedAt: _now,
);

String _text(String key, {Map<String, String>? namedArgs}) {
  if (namedArgs == null || namedArgs.isEmpty) return key;
  final values = namedArgs.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '$key(${values.map((entry) => '${entry.key}=${entry.value}').join(',')})';
}
