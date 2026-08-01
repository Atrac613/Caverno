import '../../../../core/utils/logger.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_compaction_service.dart';

/// Coordinates a single context-length retry without reading visible UI state.
final class TurnContextRetryCoordinator {
  const TurnContextRetryCoordinator._();

  static Future<bool> retry({
    required Object error,
    required List<Message>? ownerMessages,
    required Conversation? ownerConversation,
    required void Function() markForceCompaction,
    required void Function(List<Message> messages) applyReset,
    required Future<void> Function() sendAgain,
  }) async {
    if (!ConversationCompactionService.isContextLengthError(error.toString())) {
      return false;
    }
    final artifact = _artifact(ownerMessages, ownerConversation);
    if (artifact == null || !artifact.hasContent) {
      appLog(
        '[Compaction] Context-length retry skipped because no compactable history is available',
      );
      return false;
    }
    appLog(
      '[Compaction] Retrying after context-length error with '
      '${artifact.compactedMessageCount} compacted message(s)',
    );
    markForceCompaction();
    reset(ownerMessages: ownerMessages, apply: applyReset);
    await sendAgain();
    return true;
  }

  static bool hasCompactableHistory({
    required List<Message>? ownerMessages,
    required Conversation? ownerConversation,
  }) => _artifact(ownerMessages, ownerConversation)?.hasContent ?? false;

  static bool reset({
    required List<Message>? ownerMessages,
    required void Function(List<Message> messages) apply,
  }) {
    if (ownerMessages == null || ownerMessages.isEmpty) return false;
    final updatedMessages = [...ownerMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant || !lastMessage.isStreaming) {
      return false;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(content: '', error: null);
    apply(updatedMessages);
    return true;
  }

  static ConversationCompactionArtifact? _artifact(
    List<Message>? ownerMessages,
    Conversation? ownerConversation,
  ) {
    final messages = (ownerMessages ?? const <Message>[])
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    return ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: ownerConversation?.displayPlanDocument(
        isPlanning: ownerConversation.isPlanningSession,
      ),
      now: DateTime.now(),
      force: true,
    );
  }
}
