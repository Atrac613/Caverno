import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';
import 'package:caverno/features/chat/presentation/providers/prompt_token_budget_coordinator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a measured thread compacts on the projection, not the message count',
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
      reason: 'a measured prompt this far inside the window keeps its history',
    );
  });

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
}
