import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';

/// Identifies a conversation's on-disk LLM session log. Records have value
/// equality, so this doubles as a stable [sessionLogDetailsProvider] family key.
typedef SessionLogDetailsRequest = ({
  WorkspaceMode workspaceMode,
  String sessionId,
});

/// Read-only snapshot of where a conversation's session log lives and how big
/// it currently is. Surfaced by the chat/coding companion panel.
class SessionLogFileDetails {
  const SessionLogFileDetails({
    required this.path,
    required this.fileName,
    required this.exists,
    required this.sizeBytes,
    required this.loggingEnabled,
    this.modifiedAt,
  });

  /// Absolute path to the `.jsonl` log file (whether or not it exists yet).
  final String path;

  /// File name component of [path].
  final String fileName;

  /// Whether the log file has been written to disk yet.
  final bool exists;

  /// Current size of the log file in bytes (0 when it does not exist).
  final int sizeBytes;

  /// Whether session logging is currently active for this app run.
  final bool loggingEnabled;

  /// Last modification time, when the file exists.
  final DateTime? modifiedAt;

  /// Human-readable size such as `12.3 KB` or `4.0 MB`.
  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = sizeBytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}

/// Resolves the session log file details for a conversation without writing to
/// disk. Watches settings so it reflects the live logging-enabled state, and is
/// `autoDispose` so it refreshes when re-watched (e.g. after a manual refresh).
final sessionLogDetailsProvider = FutureProvider.autoDispose
    .family<SessionLogFileDetails, SessionLogDetailsRequest>((
      ref,
      request,
    ) async {
      final settings = ref.watch(settingsNotifierProvider);
      final loggingEnabled =
          LlmSessionLogStore.isEnabled(
            settingsEnabled: settings.enableLlmSessionLogs,
          ) &&
          !settings.demoMode;
      final store = ref.watch(llmSessionLogStoreProvider);
      final context = LlmSessionLogContext(
        workspaceMode: request.workspaceMode,
        sessionId: request.sessionId,
      );
      final file = await store.fileForContext(context, create: false);
      final fileName = file.path.split(RegExp(r'[\\/]')).last;
      final exists = await file.exists();
      if (!exists) {
        return SessionLogFileDetails(
          path: file.path,
          fileName: fileName,
          exists: false,
          sizeBytes: 0,
          loggingEnabled: loggingEnabled,
        );
      }
      final stat = await file.stat();
      return SessionLogFileDetails(
        path: file.path,
        fileName: fileName,
        exists: true,
        sizeBytes: stat.size,
        loggingEnabled: loggingEnabled,
        modifiedAt: stat.modified,
      );
    });
