import '../entities/conversation.dart';

/// Builds the rewind checkpoint for a conversation that just changed.
abstract final class ConversationCheckpointRecorder {
  static const int maxCheckpoints = 80;

  static Conversation record(Conversation conversation, {DateTime? now}) {
    final messages = conversation.messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (messages.isEmpty) {
      return conversation.copyWith(checkpoints: const []);
    }

    final message = messages.last;
    final messageCount = messages.length;
    final checkpoint = ConversationCheckpoint(
      messageId: message.id,
      messageCount: messageCount,
      title: conversation.title,
      createdAt: now ?? DateTime.now(),
      executionMode: conversation.executionMode,
      workflowStage: conversation.workflowStage,
      workflowSpec: conversation.workflowSpec,
      workflowSourceHash: conversation.workflowSourceHash,
      workflowDerivedAt: conversation.workflowDerivedAt,
      executionProgress: conversation.executionProgress,
      mutationGeneration: conversation.mutationGeneration,
      verificationGeneration: conversation.verificationGeneration,
      completionElicitationMutationGeneration:
          conversation.completionElicitationMutationGeneration,
      openQuestionProgress: conversation.openQuestionProgress,
      goal: conversation.goal,
      planArtifact: conversation.planArtifact,
      compactionArtifact: conversation.compactionArtifact,
    );

    final checkpoints = [
      for (final existing in conversation.checkpoints)
        if (existing.messageId != message.id &&
            existing.messageCount <= messageCount)
          existing,
      checkpoint,
    ]..sort((a, b) => a.messageCount.compareTo(b.messageCount));
    final retained = checkpoints.length <= maxCheckpoints
        ? checkpoints
        : checkpoints.sublist(checkpoints.length - maxCheckpoints);
    return conversation.copyWith(checkpoints: retained);
  }
}
