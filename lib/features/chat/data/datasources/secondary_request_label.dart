import '../../domain/entities/model_usage_role.dart';
import 'llm_session_log_store.dart';

/// Session-log request labels for secondary completions.
///
/// LL46: approval auto-review, memory extraction and planning requests were
/// 1,722 of the corpus's 2,431 unlabeled requests, so the model-input
/// inventory could not name their producer. Started from inside a chat turn,
/// such a request also inherits the turn's label through the zone, which would
/// book it under a main-loop recovery path; the role's label replaces it.
abstract final class SecondaryRequestLabel {
  static String? forRole(ModelUsageRole role) => switch (role) {
    ModelUsageRole.approvalAutoReview => 'approval auto-review',
    ModelUsageRole.memoryExtraction => 'memory extraction',
    ModelUsageRole.planning => 'planning request',
    ModelUsageRole.goalSuggestion => 'goal suggestion',
    _ => null,
  };

  /// Runs [body] under the label of the usage role in scope, when that role
  /// has one and a session-log context exists.
  static T scope<T>(T Function() body) {
    final label = forRole(ModelUsageRole.current);
    final context = LlmSessionLogContext.current;
    if (label == null || context == null) return body();
    return LlmSessionLogContext.run(context.withRequestLabel(label), body);
  }
}
