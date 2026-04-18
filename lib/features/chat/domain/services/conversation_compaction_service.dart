import '../entities/conversation_compaction_artifact.dart';
import '../entities/message.dart';

class ConversationCompactionService {
  ConversationCompactionService._();

  static const int minMessagesBeforeCompaction = 14;
  static const int recentMessagesToKeep = 8;
  static const int maxEstimatedPromptTokens = 6000;
  static const int maxSummaryBullets = 12;
  static const int maxBulletLength = 180;

  static ConversationCompactionArtifact? buildArtifact({
    required List<Message> messages,
    DateTime? now,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (!_needsCompaction(normalizedMessages)) {
      return null;
    }

    final compactedMessageCount = normalizedMessages.length - recentMessagesToKeep;
    if (compactedMessageCount <= 0) {
      return null;
    }

    final compactedMessages = normalizedMessages
        .sublist(0, compactedMessageCount)
        .toList(growable: false);
    final summary = _buildSummary(compactedMessages);
    if (summary.isEmpty) {
      return null;
    }

    return ConversationCompactionArtifact(
      summary: summary,
      compactedMessageCount: compactedMessageCount,
      retainedMessageCount: normalizedMessages.length - compactedMessageCount,
      estimatedPromptTokens: estimatePromptTokens(normalizedMessages),
      updatedAt: now ?? DateTime.now(),
    );
  }

  static bool shouldCompact(List<Message> messages) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    return _needsCompaction(normalizedMessages);
  }

  static List<Message> retainMessages({
    required List<Message> messages,
    ConversationCompactionArtifact? artifact,
  }) {
    final normalizedMessages = messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    if (artifact == null || !artifact.hasContent) {
      return normalizedMessages;
    }

    final compactedCount = artifact.compactedMessageCount;
    if (compactedCount <= 0 || compactedCount >= normalizedMessages.length) {
      return normalizedMessages;
    }

    return normalizedMessages.sublist(compactedCount);
  }

  static int estimatePromptTokens(List<Message> messages) {
    final characterCount = messages.fold<int>(0, (count, message) {
      return count + _normalizeMessageContent(message).length;
    });
    return (characterCount / 4).ceil();
  }

  static bool _needsCompaction(List<Message> messages) {
    if (messages.length < minMessagesBeforeCompaction) {
      return false;
    }
    return estimatePromptTokens(messages) > maxEstimatedPromptTokens ||
        messages.length > minMessagesBeforeCompaction;
  }

  static String _buildSummary(List<Message> messages) {
    final bullets = <String>[];

    for (final message in messages) {
      final normalizedContent = _normalizeMessageContent(message);
      if (normalizedContent.isEmpty) {
        continue;
      }

      final prefix = switch (message.role) {
        MessageRole.user => 'User',
        MessageRole.assistant => 'Assistant',
        MessageRole.system => 'System',
      };
      bullets.add('- $prefix: ${_truncate(normalizedContent)}');
      if (bullets.length >= maxSummaryBullets) {
        break;
      }
    }

    return bullets.join('\n');
  }

  static String _normalizeMessageContent(Message message) {
    final raw = message.content;
    final withoutThinkBlocks = raw.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false),
      ' ',
    );
    final withoutToolBlocks = withoutThinkBlocks.replaceAll(
      RegExp(
        r'<tool_(call|use|result)>.*?</tool_(call|use|result)>',
        dotAll: true,
        caseSensitive: false,
      ),
      ' ',
    );
    final normalized = withoutToolBlocks.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }

    if (message.imageBase64 != null) {
      return 'Image attachment shared in the conversation.';
    }
    return '';
  }

  static String _truncate(String value) {
    if (value.length <= maxBulletLength) {
      return value;
    }
    return '${value.substring(0, maxBulletLength - 1)}...';
  }
}
