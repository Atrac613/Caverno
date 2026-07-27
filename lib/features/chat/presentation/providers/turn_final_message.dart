import '../../domain/entities/message.dart';
import '../../domain/services/truncation_notice.dart';

/// How a turn's last message should be finalized.
///
/// Both finalization paths — the visible one and the detached one a background
/// turn takes — decide this the same way and then persist. They were written
/// twice and drifted: only the visible path recorded a turn-exit reason, so
/// every turn that finished while the user was reading another thread was
/// missing from the exit-reason distribution the triage tooling reads.
/// Deciding it in one place is what keeps them from drifting again.
class TurnFinalMessage {
  const TurnFinalMessage._({
    required this.useContentToolFallback,
    required this.dropLastAssistant,
    this.fallbackContent,
  });

  /// The streamed answer was empty but a content-tool continuation produced
  /// text, so the turn ends with that text rather than with nothing.
  final bool useContentToolFallback;

  /// Nothing visible was produced, so the empty assistant bubble is removed
  /// instead of being shown and persisted.
  final bool dropLastAssistant;

  final String? fallbackContent;

  /// [hasVisibleContent] answers whether an assistant message shows the user
  /// anything — reasoning and tool calls count, a bare `memory_update` does
  /// not.
  static TurnFinalMessage resolve({
    required Message lastMessage,
    required String? contentToolFallback,
    required bool Function(String content) hasVisibleContent,
  }) {
    final fallback = contentToolFallback?.trim();
    final isEmptyAssistant =
        lastMessage.role == MessageRole.assistant &&
        !hasVisibleContent(lastMessage.content);
    final useFallback =
        isEmptyAssistant && fallback != null && fallback.isNotEmpty;
    return TurnFinalMessage._(
      useContentToolFallback: useFallback,
      dropLastAssistant: isEmptyAssistant && !useFallback,
      fallbackContent: fallback,
    );
  }

  /// Returns [messages] with its last entry finalized: replaced by the
  /// fallback, dropped, or closed off with [metrics].
  ///
  /// [truncated] flags an answer cut off at the max-token limit, so the user
  /// knows the response — and any code or file content in it — is incomplete
  /// rather than being shown a silently truncated answer.
  List<Message> apply(
    List<Message> messages, {
    required MessageResponseMetrics? metrics,
    required bool truncated,
  }) {
    final updated = [...messages];
    final lastIndex = updated.length - 1;
    final lastMessage = updated[lastIndex];
    if (useContentToolFallback) {
      updated[lastIndex] = lastMessage.copyWith(
        content: fallbackContent ?? lastMessage.content,
        isStreaming: false,
        responseMetrics: metrics,
      );
    } else if (dropLastAssistant) {
      updated.removeAt(lastIndex);
    } else {
      updated[lastIndex] = lastMessage.copyWith(
        content: truncated
            ? TruncationNotice.withMaxTokenNotice(lastMessage.content)
            : lastMessage.content,
        isStreaming: false,
        responseMetrics: metrics,
      );
    }
    return updated;
  }
}
