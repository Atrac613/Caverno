import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_goal_routine_tool_definitions.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _goalMarker = 'CODING_GOAL_LIVE_OK';
const _multiTurnFirstMarker = 'CODING_GOAL_MULTI_TURN_STEP_ONE';
const _multiTurnSecondMarker = 'CODING_GOAL_MULTI_TURN_STEP_TWO';
const _budgetFirstMarker = 'CODING_GOAL_BUDGET_STEP_ONE';
const _budgetExhaustedMarker = 'CODING_GOAL_BUDGET_EXHAUSTED_OK';
const _afterCompleteMarker = 'CODING_GOAL_AFTER_COMPLETE_OK';
const _negativeCompletionMarker = 'CODING_GOAL_NOT_COMPLETE_OK';
const _disabledGoalMarker = 'CODING_GOAL_DISABLED_SHOULD_NOT_APPEAR';
const _disabledPromptMarker = 'CODING_GOAL_DISABLED_LIVE_OK';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CODING_GOAL_LIVE_CANARY'] == '1';

  test(
    'live LLM follows an active coding goal and auto-completes it',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary',
        );
        await conversations.saveCurrentGoal(
          objective:
              'Reply with the marker $_goalMarker and include the sentence '
              '"Goal complete. Tests passed." as concrete completion evidence.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 2000,
          turnBudget: 2,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Continue the active coding goal and provide concrete completion evidence.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final content = _lastAssistantContent(container);
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        final systemPrompt = dataSource.firstSystemPrompt;

        expect(
          systemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          systemPrompt,
          contains(_goalMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          systemPrompt,
          contains('Goal token budget remaining: 2000'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          systemPrompt,
          contains('Goal turn budget remaining: 2'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          content.toUpperCase(),
          contains(_goalMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);

        await notifier.sendMessage(
          'The prior active goal is already complete. Reply with exactly '
          '$_afterCompleteMarker and no extra text.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, expectedAssistantCount: 2);

        final completedPrompt = dataSource.systemPrompts.last;
        expect(
          completedPrompt,
          isNot(contains('Active coding goal for this thread:')),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          completedPrompt,
          isNot(contains(_goalMarker)),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          _lastAssistantContent(container).toUpperCase(),
          contains(_afterCompleteMarker),
          reason: _diagnostic(container, dataSource),
        );
        final goalAfterCompletedTurn = _currentGoal(container);
        expect(
          goalAfterCompletedTurn?.status,
          ConversationGoalStatus.completed,
        );
        expect(goalAfterCompletedTurn?.turnsUsed, 1);
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // LL35: the other goal tests deliberately strip tools to isolate the lexical
  // completion path, which makes them structurally blind to the `update_goal`
  // tool. This one offers the tool and asserts the real round trip: the model
  // calls it, the ChatNotifier handler resolves a real ack, and the ack text
  // comes back into the conversation. See
  // docs/grounded_verification_live_canary_gap_2026-07-21.md.
  test(
    'live LLM reports goal completion through the update_goal tool',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(
        env,
        dataSource,
        toolService: _UpdateGoalMcpToolService(),
        mcpEnabled: true,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-update-tool-canary',
        );
        await conversations.saveCurrentGoal(
          objective:
              'The work for this goal is already finished. Report it by '
              'calling the update_goal tool with completed set to true and a '
              'short message. Do not describe the completion in prose instead '
              'of calling the tool.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 4000,
          turnBudget: 3,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'The goal work is done. Report the goal as complete using the '
          'update_goal tool now.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        // The tool definition must actually have been offered, or the rest of
        // this test proves nothing about the tool path.
        final offeredUpdateGoal = dataSource.streamRequests
            .expand((request) => request)
            .any((message) => message.content.contains('update_goal'));

        // The ack text is produced only by GoalUpdateAckResolver, so seeing it
        // anywhere in the conversation proves the model called the tool and the
        // handler answered with a real verdict.
        final ackTexts = <String>[
          'Completion accepted',
          'Completion not recorded',
          'Progress logged',
          'Progress noted',
          'Logged as blocked',
        ];
        final conversationText = [
          ...dataSource.streamRequests.expand((request) => request),
        ].map((message) => message.content).join('\n');
        final observedAck = ackTexts
            .where(conversationText.contains)
            .toList(growable: false);

        expect(
          offeredUpdateGoal,
          isTrue,
          reason:
              'update_goal was never offered to the model.\n'
              '${_diagnostic(container, dataSource)}',
        );
        expect(
          observedAck,
          isNotEmpty,
          reason:
              'No update_goal ack appeared, so the model never called the '
              'tool (local tool-call fidelity is exactly the LL35 risk).\n'
              '${_diagnostic(container, dataSource)}',
        );

        // The ack alone proved only that the handler answered. What the user
        // sees is the goal chip, so assert the state transition itself.
        //
        // This checks the end-to-end outcome, NOT the attribution. Verified by
        // negative control against the live model: with the tool-completion
        // wiring disabled this assertion still passes, because the model's
        // prose after the tool call also satisfies the lexical inference. Use
        // the unit test in conversations_notifier_goal_test.dart to isolate
        // the tool path — its own negative control does fail. Do not read a
        // green run here as proof that the tool completed the goal.
        final goal = container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.goal;
        if (observedAck.contains('Completion accepted')) {
          expect(
            goal?.status,
            ConversationGoalStatus.completed,
            reason:
                'update_goal accepted the completion but the goal is still '
                '\${goal?.status}. This is the reported bug: the model is told '
                'prose is not how a goal is finished, so nothing else will '
                'finish it.\n'
                '\${_diagnostic(container, dataSource)}',
          );
          expect(goal?.completedAt, isNotNull);
        } else {
          // A rejection must not complete the goal — the ack told the model to
          // close the gaps and report again.
          expect(goal?.status, isNot(ConversationGoalStatus.completed));
        }
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM keeps an unfinished coding goal active across turns',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary-multiturn',
        );
        await conversations.saveCurrentGoal(
          objective:
              'Maintain this two-turn coding goal. On the first user turn, '
              'answer with $_multiTurnFirstMarker only. On the second user '
              'turn, answer with $_multiTurnSecondMarker and the sentence '
              '"Goal complete. Tests passed."',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 4000,
          turnBudget: 4,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'This is turn one. Follow only the first-turn part of the active goal.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, expectedAssistantCount: 1);

        final firstContent = _lastAssistantContent(container);
        final goalAfterFirstTurn = _currentGoal(container);
        expect(
          firstContent.toUpperCase(),
          contains(_multiTurnFirstMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(goalAfterFirstTurn?.status, ConversationGoalStatus.active);
        expect(goalAfterFirstTurn?.turnsUsed, 1);
        expect(
          dataSource.systemPrompts.last,
          contains('Goal turn budget remaining: 4'),
          reason: _diagnostic(container, dataSource),
        );

        await notifier.sendMessage(
          'This is turn two. Continue the same active goal and finish it now.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, expectedAssistantCount: 2);

        final secondContent = _lastAssistantContent(container);
        final finalGoal = _currentGoal(container);
        expect(
          secondContent.toUpperCase(),
          contains(_multiTurnSecondMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          dataSource.systemPrompts.last,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          dataSource.systemPrompts.last,
          contains('Goal turn budget remaining: 3'),
          reason: _diagnostic(container, dataSource),
        );
        expect(finalGoal?.status, ConversationGoalStatus.completed);
        expect(finalGoal?.turnsUsed, 2);
        expect(finalGoal?.completedAt, isNotNull);
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'live LLM negative completion evidence does not auto-complete the coding goal',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary-negative-completion',
        );
        await conversations.saveCurrentGoal(
          objective:
              'Reply with $_negativeCompletionMarker and the sentence '
              '"Not complete. Tests did not pass." Do not claim completion.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 2000,
          turnBudget: 3,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Run the negative completion canary. Follow the active goal exactly.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        expect(
          dataSource.firstSystemPrompt,
          contains(_negativeCompletionMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          _lastAssistantContent(container).toUpperCase(),
          contains(_negativeCompletionMarker),
          reason: _diagnostic(container, dataSource),
        );
        final goal = _currentGoal(container);
        expect(goal?.status, ConversationGoalStatus.active);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNull);
        expect(goal?.blockerRepeatCount, 0);
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM repeated blocker output auto-blocks the coding goal',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary-blocked',
        );
        await conversations.saveCurrentGoal(
          objective:
              'For each blocker canary turn, answer with exactly '
              '"Blocked: permission denied while reading canary settings."',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 4000,
          turnBudget: 5,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        for (var turn = 1; turn <= 3; turn += 1) {
          await notifier.sendMessage(
            'Blocker canary turn $turn. Follow the active goal exactly.',
            bypassPlanMode: true,
          );
          await _waitForChatIdle(container, expectedAssistantCount: turn);

          final content = _lastAssistantContent(container).toLowerCase();
          expect(
            content,
            contains('permission denied'),
            reason: _diagnostic(container, dataSource),
          );
          expect(
            _currentGoal(container)?.blockerRepeatCount,
            turn,
            reason: _diagnostic(container, dataSource),
          );
        }

        final goal = _currentGoal(container);
        expect(goal?.status, ConversationGoalStatus.blocked);
        expect(goal?.blockedAt, isNotNull);
        expect(
          goal?.normalizedBlockedReason?.toLowerCase(),
          contains('permission denied'),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    'live LLM does not receive disabled coding goals',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary-disabled',
        );
        await conversations.saveCurrentGoal(
          objective:
              'This disabled goal must never be injected. Marker: '
              '$_disabledGoalMarker.',
          enabled: false,
          status: ConversationGoalStatus.active,
          tokenBudget: 2000,
          turnBudget: 2,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Reply with exactly $_disabledPromptMarker and no extra text.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final systemPrompt = dataSource.firstSystemPrompt;
        expect(
          systemPrompt,
          isNot(contains('Active coding goal for this thread:')),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          systemPrompt,
          isNot(contains(_disabledGoalMarker)),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          _lastAssistantContent(container).toUpperCase(),
          contains(_disabledPromptMarker),
          reason: _diagnostic(container, dataSource),
        );
        final goal = _currentGoal(container);
        expect(goal?.enabled, isFalse);
        expect(goal?.status, ConversationGoalStatus.active);
        expect(goal?.turnsUsed, 0);
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM receives budget exhausted guidance after the turn budget is used',
    () async {
      final env = _CodingGoalLiveEnv.fromEnvironment();
      final dataSource = _CodingGoalLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildCodingGoalContainer(env, dataSource);

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'coding-goal-live-canary-budget',
        );
        await conversations.saveCurrentGoal(
          objective:
              'On the first budget canary turn, answer with $_budgetFirstMarker only. '
              'On later budget canary turns, answer with $_budgetExhaustedMarker only.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 8000,
          turnBudget: 1,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Budget canary turn one. Follow the active goal exactly.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, expectedAssistantCount: 1);

        expect(
          _lastAssistantContent(container).toUpperCase(),
          contains(_budgetFirstMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(_currentGoal(container)?.status, ConversationGoalStatus.active);
        expect(_currentGoal(container)?.turnBudgetExceeded, isTrue);

        await notifier.sendMessage(
          'Budget canary turn two. The user explicitly asks you to report the '
          'budget state, but do not claim completion and do not report a blocker.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, expectedAssistantCount: 2);

        final exhaustedPrompt = dataSource.systemPrompts.last;
        expect(
          exhaustedPrompt,
          contains('Goal turn budget remaining: 0'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          exhaustedPrompt,
          contains('The goal budget is exhausted.'),
          reason: _diagnostic(container, dataSource),
        );
        expect(
          _lastAssistantContent(container).toUpperCase(),
          contains(_budgetExhaustedMarker),
          reason: _diagnostic(container, dataSource),
        );
        expect(_currentGoal(container)?.status, ConversationGoalStatus.active);
        expect(_currentGoal(container)?.turnsUsed, 2);
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

ProviderContainer _buildCodingGoalContainer(
  _CodingGoalLiveEnv env,
  _CodingGoalLiveDataSource dataSource, {
  McpToolService? toolService,
  bool mcpEnabled = false,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(env, mcpEnabled: mcpEnabled),
      ),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        _LiveCodingProjectsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(
        toolService ?? _NoToolsMcpToolService(),
      ),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 4),
  int expectedAssistantCount = 1,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final finishedAssistantCount = state.messages
        .where(
          (message) =>
              message.role == MessageRole.assistant && !message.isStreaming,
        )
        .length;
    final hasExpectedFinishedAssistants =
        finishedAssistantCount >= expectedAssistantCount;
    if (!state.isLoading && hasExpectedFinishedAssistants) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for coding goal live canary completion.\n'
    '${_diagnostic(container, null)}',
  );
}

String _lastAssistantContent(ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  for (final message in messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message.content;
    }
  }
  return '';
}

ConversationGoal? _currentGoal(ProviderContainer container) {
  return container
      .read(conversationsNotifierProvider)
      .currentConversation
      ?.goal;
}

String _diagnostic(
  ProviderContainer container,
  _CodingGoalLiveDataSource? dataSource,
) {
  final chatState = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final messages = chatState.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
  return [
    'isLoading=${chatState.isLoading}',
    'error=${chatState.error}',
    'messages=${chatState.messages.length}',
    'goal=${jsonEncode(conversation?.goal?.toJson())}',
    'streamRequests=${dataSource?.streamRequests.length ?? 0}',
    messages,
  ].join('\n');
}

class _CodingGoalLiveEnv {
  const _CodingGoalLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;

  static _CodingGoalLiveEnv fromEnvironment() {
    return _CodingGoalLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_MAX_TOKENS'] ?? '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_TEMPERATURE'] ?? '',
          ) ??
          0.1,
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for coding goal live LLM validation.');
  }
  return value;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env, {this.mcpEnabled = false});

  final _CodingGoalLiveEnv env;

  /// Tools are off for the completion-inference tests (they isolate the
  /// lexical path). The LL35 `update_goal` test turns them on — without this
  /// the tool catalog is never sent and the tool path is unreachable.
  final bool mcpEnabled;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: mcpEnabled,
      demoMode: false,
    );
  }
}

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

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _MockConversationBox extends Mock implements Box<String> {}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _NoToolsMcpToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Tool is not available'}),
      isSuccess: false,
      errorMessage: 'Tool is not available',
    );
  }
}

/// Exposes only the `update_goal` definition so the LL35 tool path is actually
/// reachable in a live run. The definition is all this service needs to
/// provide — the ChatNotifier handler registry intercepts `update_goal` and
/// routes it to `handleUpdateGoal`, so `executeTool` is never called for it.
class _UpdateGoalMcpToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return <Map<String, dynamic>>[McpGoalRoutineToolDefinitions.updateGoalTool];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Tool is not available'}),
      isSuccess: false,
      errorMessage: 'Tool is not available',
    );
  }
}

class _CodingGoalLiveDataSource implements ChatDataSource {
  _CodingGoalLiveDataSource(this.delegate);

  final ChatRemoteDataSource delegate;
  final List<List<Message>> streamRequests = [];

  List<String> get systemPrompts {
    return streamRequests
        .expand((request) => request)
        .where(
          (message) =>
              message.role == MessageRole.system &&
              message.content.startsWith('Current local date and time'),
        )
        .map((message) => message.content)
        .toList(growable: false);
  }

  String get firstSystemPrompt {
    return systemPrompts.firstOrNull ?? '';
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final firstContent = messages.isEmpty ? '' : messages.first.content;
    if (firstContent.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      return Future.value(
        ChatCompletionResult(
          content: jsonEncode(<String, dynamic>{
            'summary': '',
            'open_loops': const <String>[],
            'profile': <String, dynamic>{
              'persona': const <String>[],
              'preferences': const <String>[],
              'do_not': const <String>[],
            },
            'memories': const <Map<String, dynamic>>[],
          }),
          finishReason: 'stop',
        ),
      );
    }
    return delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.streamWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}
