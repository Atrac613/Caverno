import 'dart:async';

const Object _modelUsageRoleZoneKey = #cavernoModelUsageRole;

/// Which part of the app issued an LLM request, for per-model usage accounting.
///
/// This is deliberately *not* derived from `LlmSessionLogContext.requestLabel`.
/// Every label value names a main-loop recovery path (`'turn opening request'`,
/// `'tool-loop exhaustion recovery'`, ...) and the roles below set no label at
/// all. Worse, a role started with `unawaited(...)` from inside a turn's
/// logging zone would *inherit* that turn's label, because zone values
/// propagate into async callbacks — so memory extraction would be booked under
/// whatever recovery path the parent turn happened to be in.
enum ModelUsageRole {
  chat,
  memoryExtraction,
  planning,
  proReasoning,
  goalSuggestion,
  approvalAutoReview,
  subagent,
  routine,
  eval,

  /// No call site claimed this request. Kept as the default so a missed entry
  /// point shows up as a visible gap instead of silently inflating [chat].
  unknown;

  /// The role in scope, or [unknown] when nothing claimed the current zone.
  static ModelUsageRole get current =>
      Zone.current[_modelUsageRoleZoneKey] as ModelUsageRole? ?? unknown;

  /// Runs [body] with this role in scope, including its async continuations.
  T runWith<T>(T Function() body) =>
      runZoned(body, zoneValues: {_modelUsageRoleZoneKey: this});

  static ModelUsageRole fromName(String name) =>
      values.firstWhere((role) => role.name == name, orElse: () => unknown);
}

/// Who a request belongs to, captured when the request is *issued*.
///
/// Reading the ambient zone when the response lands does not work: a streaming
/// completion's body runs lazily on first listen, which happens outside the
/// caller's zone, so the role and label would both come back empty. Issue time
/// is the only point where the caller's zone is still current.
final class ModelUsageAttribution {
  const ModelUsageAttribution({this.role = ModelUsageRole.unknown, this.label});

  /// Snapshots whatever is in scope right now.
  factory ModelUsageAttribution.capture({String? Function()? labelResolver}) =>
      ModelUsageAttribution(
        role: ModelUsageRole.current,
        label: labelResolver?.call(),
      );

  final ModelUsageRole role;
  final String? label;

  static const empty = ModelUsageAttribution();
}
