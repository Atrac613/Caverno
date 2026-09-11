import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/conversation_compaction_service.dart';

/// Per-thread record of how far the prompt estimator falls short of what the
/// endpoint actually charges.
///
/// The estimator sees conversation messages; the request also carries the tool
/// catalog and is tokenized by the model's own tokenizer. Pairing the estimate
/// made for a request with the prompt tokens reported for that same request
/// turns the difference into a measured quantity instead of a guess.
///
/// State is keyed by conversation so two threads running at once cannot
/// complete each other's pairs, and pending estimates are keyed by the exact
/// turn owner for the same reason.
final class PromptTokenCalibrationRegistry {
  final Map<String, PromptTokenCalibration> _byConversation =
      <String, PromptTokenCalibration>{};
  final Map<ChatTurnOwner, int> _pendingEstimates = <ChatTurnOwner, int>{};

  /// Records what was estimated for the prompt about to be sent for [owner].
  void recordEstimate({
    required ChatTurnOwner owner,
    required int estimatedPromptTokens,
  }) {
    if (estimatedPromptTokens <= 0) return;
    _pendingEstimates.removeWhere(
      (pendingOwner, _) =>
          pendingOwner.conversationId == owner.conversationId &&
          pendingOwner.interactionGeneration < owner.interactionGeneration,
    );
    _pendingEstimates[owner] = estimatedPromptTokens;
  }

  /// Completes the pair with the prompt size the endpoint reported.
  ///
  /// The largest measured shortfall for the conversation wins. A turn ends on
  /// a final answer sent without tools, whose small shortfall would otherwise
  /// erase the catalog-sized one measured moments earlier in the same turn --
  /// and it is the tool-bearing request that decides whether the next prompt
  /// fits.
  void recordMeasurement({
    required ChatTurnOwner owner,
    required int measuredPromptTokens,
  }) {
    if (measuredPromptTokens <= 0) return;
    final estimated = _pendingEstimates[owner];
    if (estimated == null || estimated <= 0) return;
    final candidate = PromptTokenCalibration(
      measuredPromptTokens: measuredPromptTokens,
      estimatedPromptTokens: estimated,
    );
    final current = _byConversation[owner.conversationId];
    if (current != null && current.uncountedTokens >= candidate.uncountedTokens) {
      return;
    }
    _byConversation[owner.conversationId] = candidate;
  }

  /// Accepts a null id so callers holding an unopened thread need no guard.
  PromptTokenCalibration forConversation(String? conversationId) =>
      conversationId == null
      ? PromptTokenCalibration.empty
      : _byConversation[conversationId] ?? PromptTokenCalibration.empty;

  /// Drops a thread's calibration, for when its request shape stops being
  /// comparable -- a different model, endpoint, or tool catalog.
  void clearConversation(String conversationId) {
    _byConversation.remove(conversationId);
    _pendingEstimates.removeWhere(
      (owner, _) => owner.conversationId == conversationId,
    );
  }

  void clear() {
    _byConversation.clear();
    _pendingEstimates.clear();
  }
}
