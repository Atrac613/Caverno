import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/tool_approval_audit_log.dart';
import '../../../core/utils/app_log_file.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../../chat/data/datasources/session_logging_chat_datasource.dart';

/// One of the local log sinks the Logging settings page can inspect and clear.
enum LogFileTarget {
  /// `~/.caverno/session_logs/<workspace>/<session>.jsonl`
  llmSessionLogs,

  /// `~/.caverno/approval_audit/<date>.jsonl`
  approvalAudit,

  /// `~/.caverno/app_logs/<date>.log`
  appLogFile,
}

/// What one target currently occupies on disk.
class LogDirectoryUsage {
  const LogDirectoryUsage({required this.fileCount, required this.totalBytes});

  static const empty = LogDirectoryUsage(fileCount: 0, totalBytes: 0);

  final int fileCount;
  final int totalBytes;

  bool get isEmpty => fileCount == 0;
}

/// Reports and clears the local log files on demand.
///
/// Deliberately manual: none of the three sinks prunes on a timer, and two of
/// them prune only while writing, so a disabled sink keeps whatever it already
/// wrote. Clearing is therefore a user action rather than a background job —
/// an agent run in progress is never silently robbed of its own trail.
///
/// Directories are left in place after a delete so their owner-only
/// permissions survive; only the files inside are removed.
class LogFileCleanupService {
  LogFileCleanupService({
    required LlmSessionLogStore sessionLogStore,
    required ToolApprovalAuditLog approvalAuditLog,
    AppLogFile? appLogFile,
    bool? enabled,
  }) : _sessionLogStore = sessionLogStore,
       _approvalAuditLog = approvalAuditLog,
       _appLogFile = appLogFile ?? AppLogFile.instance,
       // Default to a no-op under `flutter test`: the production providers
       // resolve to the developer's real `~/.caverno`, which is the same
       // corpus every roadmap measurement reads. Any widget test that mounts
       // the Logging page would otherwise scan it — and one stray tap would
       // delete it. Tests that assert on this service opt back in.
       _enabled = enabled ?? !_isFlutterTest;

  final LlmSessionLogStore _sessionLogStore;
  final ToolApprovalAuditLog _approvalAuditLog;
  final AppLogFile _appLogFile;
  final bool _enabled;

  static bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  Future<LogDirectoryUsage> usage(LogFileTarget target) async {
    if (!_enabled) return LogDirectoryUsage.empty;
    final directory = await _directoryFor(target);
    if (directory == null || !directory.existsSync()) {
      return LogDirectoryUsage.empty;
    }
    var fileCount = 0;
    var totalBytes = 0;
    try {
      await for (final entity in directory.list(
        recursive: _isRecursive(target),
        followLinks: false,
      )) {
        if (entity is! File || !_matchesTarget(target, entity)) continue;
        fileCount++;
        totalBytes += await entity.length();
      }
    } on Object {
      // A partially readable directory still reports what it managed to scan.
    }
    return LogDirectoryUsage(fileCount: fileCount, totalBytes: totalBytes);
  }

  /// Deletes every file belonging to [target] and returns how many went away.
  Future<int> deleteAll(LogFileTarget target) async {
    if (!_enabled) return 0;
    // The app log sink owns its own day-file cache, which must be dropped
    // alongside the files it points at.
    if (target == LogFileTarget.appLogFile) return _appLogFile.deleteAll();

    final directory = await _directoryFor(target);
    if (directory == null || !directory.existsSync()) return 0;
    var deleted = 0;
    try {
      final entities = await directory
          .list(recursive: _isRecursive(target), followLinks: false)
          .toList();
      for (final entity in entities) {
        if (entity is! File || !_matchesTarget(target, entity)) continue;
        try {
          await entity.delete();
          deleted++;
        } on Object {
          // Another process may hold it; report only what actually went away.
        }
      }
    } on Object {
      // Listing failed outright; the caller reports the partial count.
    }
    return deleted;
  }

  Future<Directory?> _directoryFor(LogFileTarget target) async {
    switch (target) {
      case LogFileTarget.llmSessionLogs:
        return _sessionLogStore.resolveLogDirectory();
      case LogFileTarget.approvalAudit:
        return _approvalAuditLog.resolveLogDirectory();
      case LogFileTarget.appLogFile:
        return _appLogFile.logDirectory;
    }
  }

  /// Session logs are partitioned into `chat/`, `coding/` and `routines/`
  /// subdirectories; the other two are flat day-file directories.
  bool _isRecursive(LogFileTarget target) =>
      target == LogFileTarget.llmSessionLogs;

  /// Only files this app wrote are removed, so an unrelated file that happens
  /// to sit in the directory survives.
  bool _matchesTarget(LogFileTarget target, File file) {
    final name = file.uri.pathSegments.last;
    switch (target) {
      case LogFileTarget.llmSessionLogs:
        return LlmSessionLogStore.isSessionLogFileName(name);
      case LogFileTarget.approvalAudit:
        return name.endsWith('.jsonl');
      case LogFileTarget.appLogFile:
        return name.endsWith('.log');
    }
  }
}

final logFileCleanupServiceProvider = Provider<LogFileCleanupService>((ref) {
  return LogFileCleanupService(
    sessionLogStore: ref.watch(llmSessionLogStoreProvider),
    approvalAuditLog: ref.watch(toolApprovalAuditLogProvider),
  );
});
