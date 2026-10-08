import 'dart:convert';

import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/context_window_observation_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/presentation/providers/primary_turn_route_runtime.dart';
import 'package:caverno/features/chat/presentation/providers/prompt_token_budget_coordinator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  AppSettings settingsWithWindow(int usableContextTokens) {
    final defaults = AppSettings.defaults();
    if (usableContextTokens <= 0) return defaults;
    return defaults.copyWith(
      modelCapabilityProfiles: [
        ModelCapabilityProfile(
          id: ModelCapabilityProfile.buildId(
            provider: defaults.llmProvider,
            baseUrl: ApiConstants.defaultBaseUrl,
            model: ApiConstants.defaultModel,
          ),
          provider: defaults.llmProvider,
          baseUrl: ApiConstants.defaultBaseUrl,
          model: ApiConstants.defaultModel,
          usableContextTokens: usableContextTokens,
        ),
      ],
    );
  }

  List<Message> buildMessages(int count) => List<Message>.generate(
    count,
    (index) => Message(
      id: 'message-$index',
      content: 'Turn $index.',
      role: index.isEven ? MessageRole.user : MessageRole.assistant,
      timestamp: DateTime(2026, 9, 11, 12, index),
    ),
  );

  late PromptTokenBudgetCoordinator coordinator;
  final turn = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 1,
  );

  setUp(() => coordinator = PromptTokenBudgetCoordinator());

  test('falls back to the fixed budget when no window has been probed', () {
    final budget = coordinator.budgetFor(settingsWithWindow(0), 'thread-a');

    expect(
      budget.budgetTokens,
      ConversationCompactionService.maxEstimatedPromptTokens,
    );
    expect(budget.calibration.hasMeasurement, isFalse);
  });

  test('derives the budget from the probed window', () {
    final budget = coordinator.budgetFor(settingsWithWindow(32768), 'thread-a');

    expect(
      budget.budgetTokens,
      32768 -
          ApiConstants.defaultMaxTokens -
          ConversationCompactionService.contextSafetyMarginTokens,
    );
  });

  test('carries a recorded measurement into the next budget', () {
    coordinator.recordEstimate(turn, buildMessages(4));
    coordinator.recordMeasurement(
      turn,
      ChatCompletionResult(
        content: '',
        finishReason: 'stop',
        usage: const TokenUsage(
          promptTokens: 9000,
          completionTokens: 10,
          totalTokens: 9010,
        ),
      ),
    );

    final budget = coordinator.budgetFor(settingsWithWindow(32768), 'thread-a');
    expect(budget.calibration.measuredPromptTokens, 9000);
    expect(budget.calibration.uncountedTokens, greaterThan(8000));
  });

  test(
    'a measured thread compacts on the projection, not the message count',
    () {
      final settings = settingsWithWindow(32768);

      expect(
        coordinator
            .budgetFor(settings, 'thread-a')
            .resolveArtifact(conversation: null, messages: buildMessages(16)),
        isNotNull,
        reason: 'without a measurement the message-count rule still decides',
      );

      coordinator.recordEstimate(turn, buildMessages(4));
      coordinator.recordMeasurement(
        turn,
        ChatCompletionResult(
          content: '',
          finishReason: 'stop',
          usage: const TokenUsage(
            promptTokens: 900,
            completionTokens: 10,
            totalTokens: 910,
          ),
        ),
      );

      expect(
        coordinator
            .budgetFor(settings, 'thread-a')
            .resolveArtifact(conversation: null, messages: buildMessages(16)),
        isNull,
        reason:
            'a measured prompt this far inside the window keeps its history',
      );
    },
  );

  test('clearConversation drops the thread measurement', () {
    coordinator.recordEstimate(turn, buildMessages(4));
    coordinator.recordMeasurement(
      turn,
      ChatCompletionResult(
        content: '',
        finishReason: 'stop',
        usage: const TokenUsage(
          promptTokens: 9000,
          completionTokens: 10,
          totalTokens: 9010,
        ),
      ),
    );

    coordinator.clearConversation('thread-a');

    expect(
      coordinator
          .budgetFor(settingsWithWindow(32768), 'thread-a')
          .calibration
          .hasMeasurement,
      isFalse,
    );
  });

  group('a routed turn', () {
    // Session 0372d7fb: the review route ran on another endpoint, but its
    // prompt was budgeted against the primary model's 65,536-token window.
    ModelCapabilityProfile routeProfile(int usableContextTokens) =>
        ModelCapabilityProfile(
          id: 'review',
          provider: AppSettings.defaults().llmProvider,
          baseUrl: 'https://api.example.com/v1',
          model: 'review-model',
          usableContextTokens: usableContextTokens,
        );

    test('resolves the probed window, then the published one', () {
      expect(
        PrimaryTurnRouteRuntime.usableWindow(routeProfile(400000), 'x'),
        400000,
      );
      expect(
        PrimaryTurnRouteRuntime.usableWindow(routeProfile(0), 'gpt-5.6-luna'),
        1050000,
      );
      expect(PrimaryTurnRouteRuntime.usableWindow(null, 'unlisted'), isNull);
    });

    test('budgets by the route window, else the primary window', () {
      final primary = coordinator
          .budgetFor(settingsWithWindow(65536), 'thread-a')
          .budgetTokens;
      expect(
        coordinator
            .budgetFor(
              settingsWithWindow(65536),
              'thread-a',
              route: (key: 'review', window: 400000),
            )
            .budgetTokens,
        greaterThan(primary),
      );
      for (final unknown in [null, 0]) {
        expect(
          coordinator
              .budgetFor(
                settingsWithWindow(65536),
                'thread-a',
                route: (key: 'review', window: unknown),
              )
              .budgetTokens,
          primary,
        );
      }
    });
  });

  group('context window observations', () {
    late ContextWindowObservationStore store;
    const route = (
      key: 'https://api.example.com/v1|review-model',
      window: null,
    );
    ChatCompletionResult completed(int promptTokens) => ChatCompletionResult(
      content: '',
      finishReason: 'stop',
      usage: TokenUsage(
        promptTokens: promptTokens,
        completionTokens: 1,
        totalTokens: promptTokens + 1,
      ),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ContextWindowObservationStore(
        await SharedPreferences.getInstance(),
      );
      coordinator.observeWith(store);
    });

    test('an accepted prompt proves the route window floor', () async {
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-a',
        route: route,
      );
      coordinator.recordEstimate(turn, buildMessages(4));
      coordinator.recordMeasurement(turn, completed(27575));
      expect(store.read(route.key)!.provenPromptTokens, 27575);

      // Persisted, and readable by a fresh store.
      final reloaded = ContextWindowObservationStore(
        await SharedPreferences.getInstance(),
      );
      expect(reloaded.read(route.key)!.provenPromptTokens, 27575);
    });

    test('a length rejection records the rejected size and named limit', () {
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-a',
        route: route,
      );
      coordinator.recordEstimate(turn, buildMessages(4));
      final rejected = coordinator.recordLengthFailure(
        turn,
        Exception(
          "This model's maximum context length is 128000 tokens. However, "
          'your messages resulted in 130512 tokens.',
        ),
      );
      expect(rejected, isTrue);
      final observed = store.read(route.key)!;
      expect(observed.reportedLimitTokens, 128000);
      expect(observed.failedPromptTokens, greaterThan(0));
    });

    test('other errors are not length failures and record nothing', () {
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-a',
        route: route,
      );
      expect(
        coordinator.recordLengthFailure(turn, Exception('connection reset')),
        isFalse,
      );
      expect(store.read(route.key), isNull);
    });

    test('a turn without a route records nothing', () {
      coordinator.budgetFor(settingsWithWindow(65536), 'thread-a');
      coordinator.recordEstimate(turn, buildMessages(4));
      coordinator.recordMeasurement(turn, completed(27575));
      expect(store.read(route.key), isNull);
    });
  });

  group('tool result scale', () {
    late ContextWindowObservationStore store;
    const key = 'https://api.example.com/v1|review-model';
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ContextWindowObservationStore(
        await SharedPreferences.getInstance(),
      );
      coordinator.observeWith(store);
    });

    test('a known window scales up to the cost cap', () {
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-a',
        route: (key: key, window: 1050000),
      );
      expect(
        coordinator.toolResultScale('thread-a'),
        PromptTokenBudgetCoordinator.costCapTokens /
            PromptTokenBudgetCoordinator.referenceWindowTokens,
      );
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-b',
        route: (key: 'local', window: 65536),
      );
      expect(coordinator.toolResultScale('thread-b'), 1);
    });

    test('an unknown window grows only through pressured fits', () {
      coordinator.budgetFor(
        settingsWithWindow(65536),
        'thread-a',
        route: (key: key, window: null),
      );
      expect(coordinator.toolResultScale('thread-a'), 1);
      final crowded = [
        for (var i = 0; i < 8; i++)
          ToolResultInfo(
            id: 'r$i',
            name: 'read_file',
            arguments: {'path': '/p/$i.py'},
            result: jsonEncode({
              'path': '/p/$i.py',
              'content': List.filled(9000, 'x').join(),
            }),
          ),
      ];
      coordinator.budgetToolResults(
        turn,
        crowded,
        mode: ToolResultPromptBudgetMode.normal,
        protectedPaths: const {},
        summaryFirst: false,
      );
      coordinator.recordEstimate(turn, buildMessages(4));
      coordinator.recordMeasurement(
        turn,
        ChatCompletionResult(
          content: '',
          finishReason: 'stop',
          usage: const TokenUsage(
            promptTokens: 27000,
            completionTokens: 1,
            totalTokens: 27001,
          ),
        ),
      );
      expect(coordinator.toolResultScale('thread-a'), 1.5);
      expect(
        coordinator.recordLengthFailure(
          turn,
          Exception('maximum context length is 70000 tokens'),
        ),
        isTrue,
      );
      expect(coordinator.toolResultScale('thread-a'), 1);
    });
  });
}
