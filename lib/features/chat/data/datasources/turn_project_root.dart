import 'dart:async';

final Object _turnProjectRootZoneKey = Object();

/// The coding project a turn belongs to, carried across the awaits of its tool
/// dispatch.
///
/// Relative tool paths must resolve against the project the turn was started
/// on, not the one the user happens to be looking at: on 2026-07-25 a turn on
/// run19 asked for `todo_app.md` and read run20's copy, and a relative write
/// would have landed in the wrong project. Zone-scoped rather than an ambient
/// field because parallel tool batches interleave, which would let one turn
/// overwrite another's root mid-flight.
final class TurnProjectRoot {
  const TurnProjectRoot(this.rootPath);

  final String rootPath;

  static TurnProjectRoot? get current =>
      Zone.current[_turnProjectRootZoneKey] as TurnProjectRoot?;

  static T runScoped<T>(TurnProjectRoot? root, T Function() body) {
    if (root == null) return body();
    return runZoned(body, zoneValues: {_turnProjectRootZoneKey: root});
  }
}
