import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/shell_write_observation.dart';

typedef ShellWriteCollector =
    Future<({List<String> paths, bool truncated, bool reportingConfirmed})?>
    Function(String tag);

/// Records where an observed shell command wrote outside the project.
///
/// Runs after the tool result has been handed back, and callers should not
/// await it: reading the kernel reports costs seconds of `log show`, which a
/// tool loop must not pay. Tool behaviour never depends on the outcome.
Future<void> observeShellWrites({
  required LlmSessionLogStore store,
  required bool settingsEnabled,
  required LlmSessionLogContext context,
  required String toolName,
  required String renderedPayload,
  required String toolCallId,
  ShellWriteCollector collect = ShellWriteObservation.collect,
  Duration settle = const Duration(seconds: 2),
}) async {
  final tag = ShellWriteObservation.tagFromPayload(renderedPayload);
  if (tag == null) return;
  if (!LlmSessionLogStore.isEnabled(settingsEnabled: settingsEnabled)) return;
  // The kernel delivers reports asynchronously; give the last ones time.
  await Future<void>.delayed(settle);
  final observed = await collect(tag);
  if (observed == null) return;
  await store.recordShellWriteObservation(
    context: context,
    at: DateTime.now(),
    toolName: toolName,
    tag: tag,
    paths: observed.paths,
    truncated: observed.truncated,
    reportingConfirmed: observed.reportingConfirmed,
    toolCallId: toolCallId,
  );
}
