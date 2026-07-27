import 'dart:async';

final Object _turnThreadZoneKey = Object();

/// The thread a turn belongs to, carried across the awaits of its tool
/// dispatch.
///
/// Approval prompts are raised from deep inside tool handlers that have no
/// idea which thread they are serving, so they used to land on whichever
/// thread the user was looking at. Zone-scoped for the same reason as
/// [TurnProjectRoot]: parallel tool batches interleave, and an ambient field
/// would let one turn overwrite another's identity mid-flight.
final class TurnThread {
  const TurnThread(this.conversationId);

  final String conversationId;

  static String? get currentId =>
      (Zone.current[_turnThreadZoneKey] as TurnThread?)?.conversationId;

  static T runScoped<T>(String? conversationId, T Function() body) {
    if (conversationId == null || conversationId.isEmpty) return body();
    return runZoned(
      body,
      zoneValues: {_turnThreadZoneKey: TurnThread(conversationId)},
    );
  }
}
