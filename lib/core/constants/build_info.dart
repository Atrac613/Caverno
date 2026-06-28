/// Build provenance, baked in at compile time so a runtime artifact (and the
/// session logs it writes) can be traced back to the exact source it was built
/// from.
///
/// The values are injected via `--dart-define` by `tool/safe-flutter` (and any
/// CI build that forwards the same defines). A build that did not go through
/// that path keeps the defaults, so `commit == 'unknown'` is itself a signal
/// that the binary was not produced by the standard build entry point.
///
/// Resolving git at runtime is deliberately avoided: a distributed binary is
/// detached from its source tree, so the commit must be captured at build time.
class BuildInfo {
  BuildInfo._();

  /// Short git commit hash the binary was built from, or `'unknown'`.
  static const String commit = String.fromEnvironment(
    'CAVERNO_BUILD_COMMIT',
    defaultValue: 'unknown',
  );

  /// Whether the working tree had uncommitted changes at build time. When true,
  /// [commit] alone does not fully identify the built source.
  static const bool dirty = bool.fromEnvironment(
    'CAVERNO_BUILD_DIRTY',
    defaultValue: false,
  );

  /// UTC ISO-8601 build timestamp, or `'unknown'`.
  static const String builtAt = String.fromEnvironment(
    'CAVERNO_BUILD_TIME',
    defaultValue: 'unknown',
  );

  /// Serializes build provenance for session logs. Omits empty/unknown optional
  /// fields so logs stay compact, but always includes [commit] and [dirty] so
  /// the absence of provenance is unambiguous (`commit: unknown`).
  static Map<String, dynamic> toJson() => {
    'commit': commit,
    'dirty': dirty,
    if (builtAt != 'unknown') 'builtAt': builtAt,
  };
}
