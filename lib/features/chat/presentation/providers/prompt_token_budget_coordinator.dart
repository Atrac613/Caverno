import '../../../settings/domain/entities/app_settings.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_compaction_service.dart';
import 'prompt_token_calibration_registry.dart';

/// Decides how much conversation history a prompt may carry.
///
/// Two inputs the compaction service cannot reach on its own meet here: the
/// active model's usable context window, and what the endpoint has actually
/// charged this thread for prompts of a known estimated size.
final class PromptTokenBudgetCoordinator {
  final PromptTokenCalibrationRegistry _calibrations =
      PromptTokenCalibrationRegistry();

  PromptTokenBudget budgetFor(AppSettings settings, String? conversationId) =>
      PromptTokenBudget._(
        budgetTokens: ConversationCompactionService.resolvePromptTokenBudget(
          usableContextTokens:
              settings.effectiveModelCapabilityProfile?.usableContextTokens ??
              0,
          maxResponseTokens: settings.maxTokens,
        ),
        calibration: _calibrations.forConversation(conversationId),
      );

  /// Records what was estimated for the prompt about to be sent.
  void recordEstimate(ChatTurnOwner owner, List<Message> promptMessages) {
    _calibrations.recordEstimate(
      owner: owner,
      estimatedPromptTokens: ConversationCompactionService.estimatePromptTokens(
        promptMessages
            .where((message) => !message.isStreaming)
            .toList(growable: false),
      ),
    );
  }

  /// Completes that pair with the prompt size the endpoint reported.
  void recordMeasurement(ChatTurnOwner owner, ChatCompletionResult result) =>
      _calibrations.recordMeasurement(
        owner: owner,
        measuredPromptTokens: result.usage.promptTokens,
      );

  void clearConversation(String conversationId) =>
      _calibrations.clearConversation(conversationId);
}

/// One thread's prompt allowance, and the measurement it was derived from.
final class PromptTokenBudget {
  const PromptTokenBudget._({
    required this.budgetTokens,
    required this.calibration,
  });

  final int budgetTokens;
  final PromptTokenCalibration calibration;

  ConversationTokenPressure assess(List<Message> messages) =>
      ConversationCompactionService.assessTokenPressure(
        messages: messages,
        promptTokenBudget: budgetTokens,
        calibration: calibration,
      );

  /// The summary to stand in for omitted turns, preferring a freshly built one
  /// and falling back to whatever the conversation already carries.
  ConversationCompactionArtifact? resolveArtifact({
    required Conversation? conversation,
    required List<Message> messages,
    bool forceCompaction = false,
  }) {
    final freshArtifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: conversation?.displayPlanDocument(
        isPlanning: conversation.isPlanningSession,
      ),
      now: conversation?.effectiveCompactionArtifact.updatedAt,
      force: forceCompaction,
      promptTokenBudget: budgetTokens,
      calibration: calibration,
    );
    if (freshArtifact != null) {
      return freshArtifact;
    }
    final persistedArtifact = conversation?.compactionArtifact;
    if (persistedArtifact?.hasContent ?? false) {
      return persistedArtifact;
    }
    return null;
  }
}
