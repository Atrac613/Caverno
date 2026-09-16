import '../../domain/entities/chat_turn_owner.dart';

/// Pins the prompt's wall clock to the turn that opened it.
///
/// The system prompt carries a minute-resolution clock in its "Dynamic turn
/// context" tail. Rebuilding it per request changed exactly one line inside a
/// ~20k-token prefix that was otherwise byte-stable for the whole turn, and the
/// LLM server then reported zero reused prompt tokens for that request.
///
/// Measured on session c138c465 (qwen3.8-27b-vision over llama.cpp): 34 of 35
/// requests whose in-prompt minute differed from the previous request reused
/// nothing and ran for a median 31.3s, while 19 of 20 requests that landed in
/// the same minute reused ~19.7-21.4k tokens and ran for a median 9.2s. The
/// ~22s difference is prefill the server had already done. Normalizing that one
/// line collapsed the turns' distinct system prompts from 10/8/2 down to 1 each,
/// so a pinned clock is enough to keep the whole tool loop on one prefix.
///
/// Precision is not lost: `get_current_datetime` reports the true time for the
/// turns that actually need it, and the pinned value is what the turn started
/// with rather than an arbitrary stale reading.
class TurnPromptClock {
  final Map<String, _PinnedClock> _pinned = <String, _PinnedClock>{};

  /// The clock [owner]'s turn is already using, pinning [now] the first time
  /// it asks. A null owner is an unregistered one-shot request (plan drafting,
  /// warm-up) and reads the live clock.
  DateTime pinFor(ChatTurnOwner? owner, DateTime now) => owner == null
      ? now
      : pin(
          conversationId: owner.conversationId,
          interactionGeneration: owner.interactionGeneration,
          now: now,
        );

  /// Returns the clock this turn has already been using, pinning [now] the
  /// first time the turn asks.
  ///
  /// Keyed by conversation rather than by turn, and a new generation replaces
  /// the entry, so the map holds one pin per thread and never grows with turn
  /// count. Nothing has to retire a pin: the next turn on that thread
  /// overwrites it.
  DateTime pin({
    required String conversationId,
    required int interactionGeneration,
    required DateTime now,
  }) {
    final existing = _pinned[conversationId];
    if (existing != null &&
        existing.interactionGeneration == interactionGeneration) {
      return existing.now;
    }
    _pinned[conversationId] = _PinnedClock(
      interactionGeneration: interactionGeneration,
      now: now,
    );
    return now;
  }

  int get pinnedCount => _pinned.length;
}

class _PinnedClock {
  const _PinnedClock({
    required this.interactionGeneration,
    required this.now,
  });

  final int interactionGeneration;
  final DateTime now;
}
