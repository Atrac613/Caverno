// ChatNotifier decomposition collaborator: turn-tool-catalog-source

/// The live tool catalogue as it stood the first time a turn looked at it.
///
/// [TurnToolCatalogCache] keeps one catalogue per selection, which is not
/// enough on its own: the selection grows as tools execute — every executed
/// tool adds its name — so the normal case misses that cache and rebuilds from
/// whatever the MCP layer happens to be serving right then. Session d904b342
/// rebuilt during a blink and lost the same ten search and network tools for
/// the rest of the turn, rewriting the request prefix and discarding the
/// model's cached context.
///
/// Reading the source once per turn makes a server that comes and goes mid-turn
/// unable to change the request. A server that appears mid-turn is likewise
/// ignored until the next turn: within a turn, stability is worth more than
/// recency.
final class TurnToolCatalogSource {
  TurnToolCatalogSource();

  List<Map<String, dynamic>>? _snapshot;

  /// How many times the live catalogue was read. Test-facing.
  int readCount = 0;

  List<Map<String, dynamic>> read(List<Map<String, dynamic>> Function() live) {
    final cached = _snapshot;
    if (cached != null) return cached;
    readCount += 1;
    return _snapshot = live();
  }
}
